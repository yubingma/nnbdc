package beidanci.service.bo;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.security.NoSuchProviderException;
import java.security.PublicKey;
import java.security.Signature;
import java.security.SignatureException;
import java.security.cert.CertificateException;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.core.JsonProcessingException;
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
    
    // Apple Shared Secret (自动续期订阅必填) - 请替换为你的实际密钥
    private static final String APPLE_SHARED_SECRET = "171b1c58f4114b16a5d00826042addba";

    // Apple Root CA - G3 (Base64 encoded)
    // 用于验证 StoreKit 2 JWS 签名
    private static final String APPLE_ROOT_CA_G3_BASE64 = 
        "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

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
    public Result<SubscriptionVo> verifySubscription(String userId, String receiptData, String productId, String transactionId, String platform, boolean updateBackend) {
        try {
            // 记录接收到的参数
            logger.info("开始验证订阅: productId={}, transactionId={}, platform={}, updateBackend={}, receiptDataLength={}", 
                    productId, transactionId, platform, updateBackend, receiptData != null ? receiptData.length() : 0);
            
            // 验证收据数据是否为空
            if (receiptData == null || receiptData.trim().isEmpty()) {
                logger.error("收据数据为空");
                return new Result<>(false, "收据数据为空", null);
            }

            // 查找用户 (游客模式下 userId 为 "guest")
            User user = null;
            if (userId != null && !userId.equals("guest")) {
                user = userBo.findById(userId);
                if (user == null) {
                    logger.error("用户不存在: {}", userId);
                    return new Result<>(false, "用户不存在", null);
                }
            } else {
                logger.info("游客模式下的收据验证");
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

            // 如果不是游客且需要更新后端，则更新用户订阅状态
            if (user != null && updateBackend) {
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
            }

            logger.info("订阅验证成功: productId={}, expireDate={}", 
                    verificationResult.productId, verificationResult.expiresDate);

            // 根据验证结果计算当前是否有效
            Date now = new Date();
            boolean isActive = verificationResult.expiresDate != null && verificationResult.expiresDate.after(now);

            // 构建订阅信息VO返回给客户端
            SubscriptionVo subscriptionVo = new SubscriptionVo(
                isActive,
                verificationResult.expiresDate,
                verificationResult.subscriptionType,
                isActive ? "active" : "expired",
                verificationResult.productId
            );

            return new Result<>(true, "订阅验证成功", subscriptionVo);

        } catch (IOException | IllegalArgumentException e) {
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
     * 完整验证流程：
     * 1. 验证JWS签名（证书链验证 + 签名验证）
     * 2. 解析Payload获取订阅信息
     */
    private ReceiptVerificationResult verifyJWTReceipt(String jwtToken) {
        try {
            // 1. 验证签名（生产环境必须）
            try {
                if (!verifyJWTSignature(jwtToken)) {
                    logger.error("JWT签名验证失败");
                    return new ReceiptVerificationResult(false, "JWT签名验证失败", -1, null, null, null);
                }
                logger.info("JWT签名验证通过");
            } catch (Exception e) {
                logger.error("JWT签名验证过程中发生异常", e);
                return new ReceiptVerificationResult(false, "JWT签名验证异常: " + e.getMessage(), -1, null, null, null);
            }

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
            
            // 判断订阅类型（根据productId判断）
            String subscriptionType;
            if (productId.contains("yearly") || productId.contains("annual") || productId.contains("year")) {
                subscriptionType = "annual";
            } else if (productId.contains("monthly") || productId.contains("month")) {
                subscriptionType = "monthly";
            } else {
                // 默认为月订阅
                subscriptionType = "monthly";
                logger.warn("JWT: 无法从 productId 判断订阅类型，默认为monthly: {}", productId);
            }
            
            logger.info("JWT解析成功: productId={}, expiresDate={}, type={}", 
                    productId, expiresDate, subscriptionType);
            
            return new ReceiptVerificationResult(true, "验证成功", 0, productId, expiresDate, subscriptionType);
            
        } catch (JsonProcessingException e) {
            logger.error("解析JWT收据失败", e);
            return new ReceiptVerificationResult(false, "JWT解析失败: " + e.getMessage(), -1, null, null, null);
        }
    }

    /**
     * 验证JWS签名
     */
    private boolean verifyJWTSignature(String jwt) throws Exception {
        String[] parts = jwt.split("\\.");
        if (parts.length != 3) throw new IllegalArgumentException("Invalid JWT format");

        // 1. 解析Header获取x5c
        byte[] headerBytes = Base64.getUrlDecoder().decode(parts[0]);
        JsonNode header = objectMapper.readTree(headerBytes);
        
        if (!header.has("x5c")) {
            throw new IllegalArgumentException("JWT Header缺少x5c字段");
        }
        
        JsonNode x5cParams = header.get("x5c");
        List<X509Certificate> chain = new ArrayList<>();
        CertificateFactory cf = CertificateFactory.getInstance("X.509");
        
        for (JsonNode x5c : x5cParams) {
            byte[] certBytes = Base64.getDecoder().decode(x5c.asText());
            chain.add((X509Certificate) cf.generateCertificate(new ByteArrayInputStream(certBytes)));
        }
        
        if (chain.isEmpty()) {
            throw new IllegalArgumentException("证书链为空");
        }

        // 2. 验证证书链
        // 加载Apple Root CA G3
        byte[] appleRootBytes = Base64.getDecoder().decode(APPLE_ROOT_CA_G3_BASE64);
        X509Certificate appleRoot = (X509Certificate) cf.generateCertificate(new ByteArrayInputStream(appleRootBytes));
        
        verifyCertificateChain(chain, appleRoot);
        
        // 3. 验证签名
        // JWS内容 = header + "." + payload
        byte[] content = (parts[0] + "." + parts[1]).getBytes(StandardCharsets.US_ASCII);
        byte[] signature = Base64.getUrlDecoder().decode(parts[2]);
        
        // 获取公钥 (来自Leaf证书)
        PublicKey publicKey = chain.get(0).getPublicKey();
        
        // 将Raw ECDSA签名转换为DER格式
        byte[] derSignature = transcodeSignatureToDER(signature);
        
        Signature sig = Signature.getInstance("SHA256withECDSA");
        sig.initVerify(publicKey);
        sig.update(content);
        
        return sig.verify(derSignature);
    }
    
    /**
     * 验证证书链
     */
    private void verifyCertificateChain(List<X509Certificate> chain, X509Certificate trustedRoot) throws Exception {
        // 1. 验证链的完整性和签名
        for (int i = 0; i < chain.size(); i++) {
            X509Certificate cert = chain.get(i);
            
            // 检查有效期
            cert.checkValidity();
            
            if (i < chain.size() - 1) {
                // 验证被下一级(Inter)签名
                X509Certificate issuer = chain.get(i + 1);
                cert.verify(issuer.getPublicKey());
            } else {
                // 最后一级(Inter或Root)必须被Trusted Root签名，或者它自己就是Trusted Root
                // 这里的chain通常不包含Root，或者包含Root。
                // 我们直接验证最后一个证书是否由Trusted Root签名
                try {
                    cert.verify(trustedRoot.getPublicKey());
                } catch (InvalidKeyException | NoSuchAlgorithmException | NoSuchProviderException | SignatureException | CertificateException e) {
                     // 如果最后一个证书就是Root（自签名），再试一次
                     if (cert.equals(trustedRoot)) {
                         return;
                     }
                     throw new Exception("证书链未锚定到受信任的Apple Root CA", e);
                }
            }
        }
    }

    /**
     * 将ECDSA Raw Signature (R|S) 转换为 DER格式
     * Java Security Signature verify需要DER格式
     */
    private byte[] transcodeSignatureToDER(byte[] jwsSignature) throws IOException {
        // Raw Signature is 64 bytes (R=32, S=32)
        if (jwsSignature.length != 64) {
            // 某些库可能有些微不同，但ES256标准是64字节
            throw new IOException("ECDSA Signature length is not 64 bytes");
        }
        
        byte[] rBytes = new byte[32];
        byte[] sBytes = new byte[32];
        System.arraycopy(jwsSignature, 0, rBytes, 0, 32);
        System.arraycopy(jwsSignature, 32, sBytes, 0, 32);
        
        // 使用BigInteger转换，它是正数 (signum=1)
        BigInteger r = new BigInteger(1, rBytes);
        BigInteger s = new BigInteger(1, sBytes);
        
        // toByteArray() 返回 ASN.1 兼容的字节 (minimum number of bytes, with sign bit)
        byte[] rDer = r.toByteArray();
        byte[] sDer = s.toByteArray();
        
        // 构建DER序列: 0x30 | totalLen | 0x02 | rLen | r | 0x02 | sLen | s
        int len = 2 + rDer.length + 2 + sDer.length;
        // DER sequence total length usually < 128, so 1 byte len is fine. 
        // Strict check: if len > 127 needed, but here max is ~70-72 bytes.
        
        byte[] der = new byte[2 + len];
        int offset = 0;
        der[offset++] = 0x30;
        der[offset++] = (byte) len;
        
        der[offset++] = 0x02;
        der[offset++] = (byte) rDer.length;
        System.arraycopy(rDer, 0, der, offset, rDer.length);
        offset += rDer.length;
        
        der[offset++] = 0x02;
        der[offset++] = (byte) sDer.length;
        System.arraycopy(sDer, 0, der, offset, sDer.length);
        
        return der;
    }

    /**
     * 向Apple服务器验证收据
     */
    private ReceiptVerificationResult verifyReceipt(String receiptData, String verifyUrl) throws IOException {
        try {
            // 验证收据数据不为空
            if (receiptData == null || receiptData.isEmpty()) {
                logger.error("收据数据为空或null");
                return new ReceiptVerificationResult(false, "收据数据为空", -1, null, null, null);
            }
            
            // 记录原始收据数据的长度和前100个字符（用于调试）
            logger.info("原始收据数据长度: {}", receiptData.length());
            if (receiptData.length() > 0) {
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
            // 共享密钥 (Shared Secret) - 自动续期订阅必须提供
            requestMap.put("password", APPLE_SHARED_SECRET);

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
                logger.error("Apple 收据验证请求失败：{}", response.code());
                return new ReceiptVerificationResult(false, "验证请求失败", response.code(), null, null, null);
            }
            
            // 解析响应 - 先检查 body 是否为 null
            okhttp3.ResponseBody responseBodyObj = response.body();
            if (responseBodyObj == null) {
                logger.error("Apple 收据验证响应体为空");
                return new ReceiptVerificationResult(false, "验证响应体为空", -1, null, null, null);
            }
                        
            String responseBody = responseBodyObj.string();
            
            // 记录完整的响应体（用于调试）
            logger.info("Apple收据验证完整响应: {}", responseBody);
            
            JsonNode jsonResponse = objectMapper.readTree(responseBody);

            int status = jsonResponse.get("status").asInt();
            
            // 状态码0表示成功
            if (status == 0) {
                JsonNode receipt = jsonResponse.get("receipt");
                JsonNode latestReceiptInfo = jsonResponse.get("latest_receipt_info");
                
                // 获取最佳订阅信息（如果有多个订阅，选择有效期最长且仍然有效的）
                JsonNode subscriptionInfo = null;
                if (latestReceiptInfo != null && latestReceiptInfo.isArray() && latestReceiptInfo.size() > 0) {
                    // 遍历所有订阅，找到有效期最长的
                    Date latestExpiresDate = null;
                    JsonNode bestSubscription = null;
                    
                    logger.info("找到 {} 个订阅记录，开始选择最佳订阅", latestReceiptInfo.size());
                    
                    for (int i = 0; i < latestReceiptInfo.size(); i++) {
                        JsonNode sub = latestReceiptInfo.get(i);
                        if (sub.has("product_id") && sub.has("expires_date_ms")) {
                            String productId = sub.get("product_id").asText();
                            long expiresDateMs = sub.get("expires_date_ms").asLong();
                            Date expiresDate = new Date(expiresDateMs);
                            
                            logger.info("订阅[{}]: productId={}, expiresDate={}", i, productId, expiresDate);
                            
                            // 选择有效期最晚的订阅
                            if (latestExpiresDate == null || expiresDate.after(latestExpiresDate)) {
                                latestExpiresDate = expiresDate;
                                bestSubscription = sub;
                                logger.info("更新最佳订阅为: productId={}, expiresDate={}", productId, expiresDate);
                            }
                        }
                    }
                    
                    subscriptionInfo = bestSubscription;
                } else if (receipt != null && receipt.has("in_app")) {
                    JsonNode inApp = receipt.get("in_app");
                    if (inApp.isArray() && inApp.size() > 0) {
                        // 同样选择有效期最长的
                        Date latestExpiresDate = null;
                        JsonNode bestSubscription = null;
                        
                        logger.info("从in_app找到 {} 个订阅记录，开始选择最佳订阅", inApp.size());
                        
                        for (int i = 0; i < inApp.size(); i++) {
                            JsonNode sub = inApp.get(i);
                            if (sub.has("product_id") && sub.has("expires_date_ms")) {
                                String productId = sub.get("product_id").asText();
                                long expiresDateMs = sub.get("expires_date_ms").asLong();
                                Date expiresDate = new Date(expiresDateMs);
                                
                                logger.info("in_app订阅[{}]: productId={}, expiresDate={}", i, productId, expiresDate);
                                
                                if (latestExpiresDate == null || expiresDate.after(latestExpiresDate)) {
                                    latestExpiresDate = expiresDate;
                                    bestSubscription = sub;
                                    logger.info("更新最佳订阅为: productId={}, expiresDate={}", productId, expiresDate);
                                }
                            }
                        }
                        
                        subscriptionInfo = bestSubscription;
                    }
                }

                if (subscriptionInfo == null) {
                    return new ReceiptVerificationResult(false, "未找到订阅信息", status, null, null, null);
                }

                // 解析订阅信息
                String productId = subscriptionInfo.get("product_id").asText();
                long expiresDateMs = subscriptionInfo.get("expires_date_ms").asLong();
                Date expiresDate = new Date(expiresDateMs);
                
                // 判断订阅类型（根据productId判断）
                String subscriptionType;
                if (productId.contains("yearly") || productId.contains("annual") || productId.contains("year")) {
                    subscriptionType = "annual";
                } else if (productId.contains("monthly") || productId.contains("month")) {
                    subscriptionType = "monthly";
                } else {
                    // 默认为月订阅
                    subscriptionType = "monthly";
                    logger.warn("无法从 productId 判断订阅类型，默认为monthly: {}", productId);
                }
                
                logger.info("最终选择的订阅: productId={}, expiresDate={}, type={}", productId, expiresDate, subscriptionType);

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
        return switch (status) {
            case 21000 -> "App Store无法读取你提供的JSON数据";
            case 21002 -> "receipt-data属性中的数据格式错误或丢失";
            case 21003 -> "收据无法验证";
            case 21004 -> "你提供的共享密钥与账户的共享密钥不匹配";
            case 21005 -> "收据服务器当前不可用";
            case 21006 -> "此收据有效，但订阅已过期";
            case 21007 -> "此收据来自测试环境，但被发送到生产环境进行验证";
            case 21008 -> "此收据来自生产环境，但被发送到测试环境进行验证";
            case 21010 -> "此收据无法被授权";
            default -> "未知错误 (状态码: " + status + ")";
        };
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

        logger.info("更新用户订阅状态: platform=ios, isPremium={}, expireDate={}, type={}", 
                isActive, expiresDate, verificationResult.subscriptionType);
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
                            logger.info("iOS订阅恢复成功");
                            return new Result<>(true, "恢复购买成功", null);
                        } catch (IllegalAccessException e) {
                            logger.error("更新iOS订阅状态失败", e);
                        }
                    }
                } catch (IOException | IllegalArgumentException e) {
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

