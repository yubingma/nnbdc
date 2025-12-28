package beidanci.service.bo;

import java.io.IOException;
import java.util.Date;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import beidanci.api.Result;
import beidanci.service.po.User;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

/**
 * 订阅相关业务逻辑
 * 处理iOS应用内购买订阅的验证和管理
 */
@Service
public class SubscriptionBo extends BaseBo<User> {

    private static final Logger logger = LoggerFactory.getLogger(SubscriptionBo.class);

    // Apple收据验证URL
    private static final String APPLE_VERIFY_RECEIPT_URL_PRODUCTION = "https://buy.itunes.apple.com/verifyReceipt";
    private static final String APPLE_VERIFY_RECEIPT_URL_SANDBOX = "https://sandbox.itunes.apple.com/verifyReceipt";
    
    // 收据验证请求的Content-Type
    private static final MediaType JSON = MediaType.get("application/json; charset=utf-8");

    private final OkHttpClient httpClient = new OkHttpClient();
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Autowired
    private UserBo userBo;

    /**
     * 验证订阅收据并更新用户订阅状态（仅支持iOS平台）
     * 
     * @param userId 用户ID
     * @param receiptData Base64编码的收据数据
     * @param productId 产品ID
     * @param transactionId 交易ID
     * @param platform 平台类型：ios（仅支持iOS）
     * @return 验证结果
     */
    @Transactional
    public Result<Void> verifySubscription(String userId, String receiptData, String productId, String transactionId, String platform) {
        try {
            // 查找用户
            User user = userBo.findById(userId);
            if (user == null) {
                logger.error("用户不存在: {}", userId);
                return new Result<>(false, "用户不存在", null);
            }

            // 验证平台参数（只支持iOS）
            if (platform == null || !platform.equals("ios")) {
                logger.error("无效的平台参数: {}，只支持iOS平台", platform);
                return new Result<>(false, "订阅功能仅支持iOS平台", null);
            }

            // 验证iOS收据
            ReceiptVerificationResult verificationResult = verifyReceiptWithApple(receiptData);

            if (!verificationResult.isValid) {
                logger.error("收据验证失败: {}", verificationResult.errorMessage);
                return new Result<>(false, verificationResult.errorMessage, null);
            }

            // 检查产品ID是否匹配
            if (!verificationResult.productId.equals(productId)) {
                logger.warn("产品ID不匹配: 期望 {}, 实际 {}", productId, verificationResult.productId);
            }

            // 更新用户订阅状态（iOS平台）
            updateUserSubscription(user, verificationResult);

            // 保存收据数据（用于恢复购买）
            user.setLastReceiptDataIos(receiptData);
            try {
                userBo.updateEntity(user);
                // 服务端主动变更用户订阅字段后，写入 user_db_log，确保客户端同步可见
                userBo.logUserUpdateForSync(user);
            } catch (IllegalAccessException e) {
                logger.error("更新用户订阅状态失败", e);
                return new Result<>(false, "更新用户订阅状态失败", null);
            }

            logger.info("订阅验证成功: userId={}, productId={}, expireDate={}", 
                    userId, verificationResult.productId, verificationResult.expiresDate);

            return new Result<>(true, "订阅验证成功", null);

        } catch (Exception e) {
            logger.error("验证订阅异常", e);
            return new Result<>(false, "验证订阅失败: " + e.getMessage(), null);
        }
    }

    /**
     * 验证收据（先尝试生产环境，失败则尝试沙盒环境）
     */
    private ReceiptVerificationResult verifyReceiptWithApple(String receiptData) throws IOException {
        // 先尝试生产环境
        ReceiptVerificationResult result = verifyReceipt(receiptData, APPLE_VERIFY_RECEIPT_URL_PRODUCTION);
        
        // 如果返回21007错误码，说明是沙盒收据，需要切换到沙盒环境
        if (result.statusCode == 21007) {
            logger.info("检测到沙盒收据，切换到沙盒环境验证");
            result = verifyReceipt(receiptData, APPLE_VERIFY_RECEIPT_URL_SANDBOX);
        }

        return result;
    }

    /**
     * 向Apple服务器验证收据
     */
    private ReceiptVerificationResult verifyReceipt(String receiptData, String verifyUrl) throws IOException {
        try {
            // 构建请求体
            String requestBody = String.format("{\"receipt-data\":\"%s\"}", receiptData);
            RequestBody body = RequestBody.create(requestBody, JSON);

            // 构建请求
            Request request = new Request.Builder()
                    .url(verifyUrl)
                    .post(body)
                    .build();

            // 发送请求
            Response response = httpClient.newCall(request).execute();
            if (!response.isSuccessful()) {
                logger.error("Apple收据验证请求失败: {}", response.code());
                return new ReceiptVerificationResult(false, "验证请求失败", response.code(), null, null, null);
            }

            // 解析响应
            String responseBody = response.body().string();
            JsonNode jsonResponse = objectMapper.readTree(responseBody);

            int status = jsonResponse.get("status").asInt();
            
            // 状态码0表示成功
            if (status == 0) {
                JsonNode receipt = jsonResponse.get("receipt");
                JsonNode latestReceiptInfo = jsonResponse.get("latest_receipt_info");
                
                // 获取最新的订阅信息（如果有多个订阅，取最新的）
                JsonNode subscriptionInfo = null;
                if (latestReceiptInfo != null && latestReceiptInfo.isArray() && latestReceiptInfo.size() > 0) {
                    subscriptionInfo = latestReceiptInfo.get(latestReceiptInfo.size() - 1);
                } else if (receipt != null && receipt.has("in_app")) {
                    JsonNode inApp = receipt.get("in_app");
                    if (inApp.isArray() && inApp.size() > 0) {
                        subscriptionInfo = inApp.get(inApp.size() - 1);
                    }
                }

                if (subscriptionInfo == null) {
                    return new ReceiptVerificationResult(false, "未找到订阅信息", status, null, null, null);
                }

                // 解析订阅信息
                String productId = subscriptionInfo.get("product_id").asText();
                long expiresDateMs = subscriptionInfo.get("expires_date_ms").asLong();
                Date expiresDate = new Date(expiresDateMs);
                
                // 判断订阅类型
                String subscriptionType = productId.contains("monthly") ? "monthly" : "annual";

                return new ReceiptVerificationResult(true, "验证成功", status, productId, expiresDate, subscriptionType);

            } else {
                // 处理错误状态码
                String errorMessage = getErrorMessage(status);
                logger.error("Apple收据验证失败: status={}, message={}", status, errorMessage);
                return new ReceiptVerificationResult(false, errorMessage, status, null, null, null);
            }

        } catch (IOException e) {
            logger.error("验证收据时发生IO异常", e);
            throw e;
        } catch (Exception e) {
            logger.error("验证收据时发生异常", e);
            return new ReceiptVerificationResult(false, "验证异常: " + e.getMessage(), -1, null, null, null);
        }
    }

    /**
     * 根据状态码获取错误信息
     */
    private String getErrorMessage(int status) {
        switch (status) {
            case 21000:
                return "App Store无法读取你提供的JSON数据";
            case 21002:
                return "receipt-data属性中的数据格式错误或丢失";
            case 21003:
                return "收据无法验证";
            case 21004:
                return "你提供的共享密钥与账户的共享密钥不匹配";
            case 21005:
                return "收据服务器当前不可用";
            case 21006:
                return "此收据有效，但订阅已过期";
            case 21007:
                return "此收据来自测试环境，但被发送到生产环境进行验证";
            case 21008:
                return "此收据来自生产环境，但被发送到测试环境进行验证";
            case 21010:
                return "此收据无法被授权";
            default:
                return "未知错误 (状态码: " + status + ")";
        }
    }

    /**
     * 更新用户订阅状态（iOS平台）
     */
    private void updateUserSubscription(User user, ReceiptVerificationResult verificationResult) {
        Date now = new Date();
        Date expiresDate = verificationResult.expiresDate;

        // 检查订阅是否过期
        boolean isActive = expiresDate != null && expiresDate.after(now);

        // 更新iOS订阅字段
        user.setIsPremiumIos(isActive);
        user.setSubscriptionExpireDateIos(expiresDate);
        user.setSubscriptionTypeIos(verificationResult.subscriptionType);
        user.setSubscriptionStatusIos(isActive ? "active" : "expired");

        logger.info("更新用户订阅状态: userId={}, platform=ios, isPremium={}, expireDate={}, type={}", 
                user.getId(), isActive, expiresDate, verificationResult.subscriptionType);
    }

    /**
     * 恢复购买（通过用户ID查找历史订阅）
     */
    @Transactional
    public Result<Void> restoreSubscription(String userId) {
        try {
            User user = userBo.findById(userId);
            if (user == null) {
                return new Result<>(false, "用户不存在", null);
            }

            // 恢复iOS订阅
            if (user.getLastReceiptDataIos() != null && !user.getLastReceiptDataIos().isEmpty()) {
                try {
                    ReceiptVerificationResult verificationResult = verifyReceiptWithApple(user.getLastReceiptDataIos());
                    if (verificationResult.isValid) {
                        updateUserSubscription(user, verificationResult);
                        try {
                            userBo.updateEntity(user);
                            logger.info("iOS订阅恢复成功: userId={}", userId);
                            return new Result<>(true, "恢复购买成功", null);
                        } catch (IllegalAccessException e) {
                            logger.error("更新iOS订阅状态失败", e);
                        }
                    }
                } catch (Exception e) {
                    logger.warn("恢复iOS订阅失败", e);
                }
            }
            
            return new Result<>(false, "未找到有效的订阅记录", null);

        } catch (Exception e) {
            logger.error("恢复购买异常", e);
            return new Result<>(false, "恢复购买失败: " + e.getMessage(), null);
        }
    }

    /**
     * 收据验证结果
     */
    private static class ReceiptVerificationResult {
        boolean isValid;
        String errorMessage;
        int statusCode;
        String productId;
        Date expiresDate;
        String subscriptionType;

        ReceiptVerificationResult(boolean isValid, String errorMessage, int statusCode, 
                                 String productId, Date expiresDate, String subscriptionType) {
            this.isValid = isValid;
            this.errorMessage = errorMessage;
            this.statusCode = statusCode;
            this.productId = productId;
            this.expiresDate = expiresDate;
            this.subscriptionType = subscriptionType;
        }
    }
}

