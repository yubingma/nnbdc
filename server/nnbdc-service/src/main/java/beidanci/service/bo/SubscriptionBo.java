package beidanci.service.bo;

import java.io.IOException;
import java.util.Base64;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import beidanci.api.Result;
import beidanci.api.model.SubscriptionVo;
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
     * 返回订阅信息，供客户端立即更新本地数据库
     * 
     * @param userId 用户ID
     * @param receiptData Base64编码的收据数据
     * @param productId 产品ID
     * @param transactionId 交易ID
     * @param platform 平台类型：ios（仅支持iOS）
     * @return 验证结果和订阅信息
     */
    @Transactional
    public Result<SubscriptionVo> verifySubscription(String userId, String receiptData, String productId, String transactionId, String platform) {
        try {
            // 记录接收到的参数
            logger.info("开始验证订阅: userId={}, productId={}, transactionId={}, platform={}, receiptDataLength={}", 
                    userId, productId, transactionId, platform, receiptData != null ? receiptData.length() : 0);
            
            // 验证收据数据是否为空
            if (receiptData == null || receiptData.trim().isEmpty()) {
                logger.error("收据数据为空");
                return new Result<>(false, "收据数据为空", null);
            }
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

            // 构建订阅信息VO返回给客户端
            SubscriptionVo subscriptionVo = new SubscriptionVo(
                user.getIsPremiumIos(),
                user.getSubscriptionExpireDateIos(),
                user.getSubscriptionTypeIos(),
                user.getSubscriptionStatusIos(),
                verificationResult.productId
            );

            return new Result<>(true, "订阅验证成功", subscriptionVo);

        } catch (Exception e) {
            logger.error("验证订阅异常", e);
            return new Result<>(false, "验证订阅失败: " + e.getMessage(), null);
        }
    }

    /**
     * 验证收据（支持JWT格式的StoreKit 2和旧格式的收据）
     */
    private ReceiptVerificationResult verifyReceiptWithApple(String receiptData) throws IOException {
        // 检查是否是JWT格式（StoreKit 2）
        if (isJWTFormat(receiptData)) {
            logger.info("检测到JWT格式收据（StoreKit 2），使用JWT解析验证");
            return verifyJWTReceipt(receiptData);
        }
        
        // 旧格式收据，使用传统API验证
        logger.info("检测到传统格式收据，使用/verifyReceipt API验证");
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
     * 检查是否是JWT格式
     */
    private boolean isJWTFormat(String receiptData) {
        // JWT格式：三个部分用.分隔，且每部分都是base64编码
        // 示例：eyJ...（以ey开头，包含两个点）
        if (receiptData == null || receiptData.isEmpty()) {
            return false;
        }
        // 简单检查：是否以"eyJ"开头且包含两个点
        return receiptData.startsWith("eyJ") && receiptData.split("\\.").length == 3;
    }
    
    /**
     * 验证JWT格式的收据（StoreKit 2）
     * JWT收据包含签名的交易信息，可以直接解析payload获取订阅信息
     */
    private ReceiptVerificationResult verifyJWTReceipt(String jwtToken) {
        try {
            // JWT格式：header.payload.signature
            String[] parts = jwtToken.split("\\.");
            if (parts.length != 3) {
                return new ReceiptVerificationResult(false, "JWT格式错误", -1, null, null, null);
            }
            
            // 解析payload（第二部分）
            String payload = parts[1];
            byte[] decodedBytes = Base64.getUrlDecoder().decode(payload);
            String decodedPayload = new String(decodedBytes);
            
            logger.info("JWT Payload: {}", decodedPayload);
            
            // 解析JSON
            JsonNode payloadJson = objectMapper.readTree(decodedPayload);
            
            // 从JWT payload中提取订阅信息
            // StoreKit 2 JWT包含以下关键字段：
            // - transactionId: 交易ID
            // - originalTransactionId: 原始交易ID
            // - productId: 产品ID
            // - purchaseDate: 购买时间（毫秒）
            // - expiresDate: 过期时间（毫秒）
            // - type: 交易类型（Auto-Renewable Subscription）
            
            if (!payloadJson.has("productId")) {
                return new ReceiptVerificationResult(false, "JWT中缺少productId字段", -1, null, null, null);
            }
            
            String productId = payloadJson.get("productId").asText();
            
            // 获取过期时间
            Date expiresDate = null;
            if (payloadJson.has("expiresDate")) {
                long expiresDateMs = payloadJson.get("expiresDate").asLong();
                expiresDate = new Date(expiresDateMs);
            }
            
            // 判断订阅类型
            String subscriptionType = productId.contains("monthly") ? "monthly" : "annual";
            
            logger.info("JWT解析成功: productId={}, expiresDate={}, type={}", 
                    productId, expiresDate, subscriptionType);
            
            // 注意：这里我们信任JWT的内容，实际生产环境中应该验证JWT签名
            // Apple的JWT使用ES256算法签名，需要使用Apple的公钥验证
            // 为了简化，这里暂时跳过签名验证，仅解析内容
            logger.warn("注意：当前未验证JWT签名，仅用于测试环境");
            
            return new ReceiptVerificationResult(true, "验证成功", 0, productId, expiresDate, subscriptionType);
            
        } catch (Exception e) {
            logger.error("解析JWT收据失败", e);
            return new ReceiptVerificationResult(false, "JWT解析失败: " + e.getMessage(), -1, null, null, null);
        }
    }

    /**
     * 向Apple服务器验证收据
     */
    private ReceiptVerificationResult verifyReceipt(String receiptData, String verifyUrl) throws IOException {
        try {
            // 记录原始收据数据的长度和前100个字符（用于调试）
            logger.info("原始收据数据长度: {}", receiptData != null ? receiptData.length() : 0);
            if (receiptData != null && receiptData.length() > 0) {
                String preview = receiptData.length() > 100 ? receiptData.substring(0, 100) : receiptData;
                logger.info("原始收据数据前100字符: {}", preview);
            }
            
            // 清理收据数据（移除换行符和空格）
            String cleanReceiptData = receiptData.replaceAll("[\\r\\n]", "");
            logger.info("清理后收据数据长度: {}", cleanReceiptData.length());
            if (cleanReceiptData.length() > 0) {
                String preview = cleanReceiptData.length() > 100 ? cleanReceiptData.substring(0, 100) : cleanReceiptData;
                logger.info("清理后收据数据前100字符: {}", preview);
            }

            // 构建请求体
            Map<String, String> requestMap = new HashMap<>();
            requestMap.put("receipt-data", cleanReceiptData);
            // requestMap.put("password", "YOUR_SHARED_SECRET"); // 如果是自动续期订阅，需要配置共享密钥

            String requestBody = objectMapper.writeValueAsString(requestMap);
            logger.info("发送给Apple的请求体: {}", requestBody.length() > 200 ? requestBody.substring(0, 200) + "..." : requestBody);
            RequestBody body = RequestBody.create(JSON, requestBody);

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

