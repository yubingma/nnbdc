package beidanci.service.util;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.aliyuncs.DefaultAcsClient;
import com.aliyuncs.IAcsClient;
import com.aliyuncs.CommonRequest;
import com.aliyuncs.CommonResponse;
import com.aliyuncs.http.MethodType;
import com.aliyuncs.profile.DefaultProfile;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import beidanci.service.config.AliyunCdnProperties;

/**
 * 阿里云资源管理工具类
 * 用于查询账户余额和付费服务使用情况
 */
@Component
public class AliyunResourceUtil {

    private static final Logger logger = LoggerFactory.getLogger(AliyunResourceUtil.class);

    @Autowired
    private AliyunCdnProperties properties;

    private IAcsClient client;
    
    private final ObjectMapper objectMapper = new ObjectMapper();

    private void initClient() {
        try {
            String accessKeyId = properties.getAccessKeyId();
            String accessKeySecret = properties.getAccessKeySecret();
            String regionId = properties.getRegionId();
            if (isBlank(accessKeyId) || isBlank(accessKeySecret)) {
                logger.error("阿里云凭据未配置：请在 application.yml 中配置 aliyun.cdn.access-key-id/secret");
                client = null;
                return;
            }
            if (isBlank(regionId)) {
                regionId = "cn-hangzhou";
            }
            DefaultProfile profile = DefaultProfile.getProfile(regionId, accessKeyId, accessKeySecret);
            client = new DefaultAcsClient(profile);
        } catch (Exception e) {
            logger.error("初始化阿里云客户端失败", e);
            client = null;
        }
    }

    private boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }

    /**
     * 查询账户余额
     * @return 账户余额信息
     */
    @SuppressWarnings("deprecation")
    public AccountBalanceInfo queryAccountBalance() {
        try {
            if (client == null) {
                initClient();
            }
            if (client == null) {
                return new AccountBalanceInfo("CDN client not initialized", null, null, null, null);
            }

            CommonRequest request = new CommonRequest();
            request.setMethod(MethodType.POST);
            request.setDomain("business.aliyuncs.com");
            request.setVersion("2017-12-14");
            request.setAction("QueryAccountBalance");

            CommonResponse response = client.getCommonResponse(request);
            JsonNode responseObj = objectMapper.readTree(response.getData());
            
            logger.info("阿里云API原始响应：{}", response.getData());

            String code = responseObj.get("Code").asText();
            if ("Success".equals(code) || "200".equals(code)) {
                JsonNode data = responseObj.get("Data");
                logger.info("账户余额查询成功，可用余额：{}", data.get("AvailableAmount").asText());
                return new AccountBalanceInfo(
                    "查询成功",
                    data.get("AvailableAmount").asText(),
                    data.get("AvailableCashAmount").asText(),
                    data.get("CreditAmount").asText(),
                    data.get("Currency").asText()
                );
            } else {
                logger.error("账户余额查询失败，Code：{}，Message：{}", code, responseObj.get("Message").asText());
                return new AccountBalanceInfo(responseObj.get("Message").asText(), null, null, null, null);
            }
        } catch (Exception e) {
            logger.error("账户余额查询异常", e);
            return new AccountBalanceInfo(e.getMessage(), null, null, null, null);
        }
    }

    /**
     * 查询资源包使用情况
     * @return 资源包使用情况
     */
    @SuppressWarnings("deprecation")
    public String queryResourcePackageInstances() {
        try {
            if (client == null) {
                initClient();
            }
            if (client == null) {
                return "CDN client not initialized";
            }

            CommonRequest request = new CommonRequest();
            request.setMethod(MethodType.POST);
            request.setDomain("business.aliyuncs.com");
            request.setVersion("2017-12-14");
            request.setAction("QueryResourcePackageInstances");

            CommonResponse response = client.getCommonResponse(request);
            JsonNode responseObj = objectMapper.readTree(response.getData());
            
            logger.info("资源包API原始响应：{}", response.getData());

            String code = responseObj.get("Code").asText();
            if ("Success".equals(code) || "200".equals(code)) {
                JsonNode data = responseObj.get("Data");
                int count = data.get("Instances") != null ? data.get("Instances").size() : 0;
                logger.info("资源包查询成功，找到 {} 个资源包", count);
                // 返回完整的Data对象JSON字符串
                return data.toString();
            } else {
                logger.error("资源包查询失败，Code：{}，Message：{}", code, responseObj.get("Message").asText());
                return responseObj.get("Message").asText();
            }
        } catch (Exception e) {
            logger.error("资源包查询异常", e);
            return e.getMessage();
        }
    }

    /**
     * 账户余额信息类
     */
    public static class AccountBalanceInfo {
        private String message;
        private String availableAmount; // 可用余额
        private String availableCashAmount; // 可用现金
        private String creditAmount; // 信用额度
        private String currency; // 币种

        public AccountBalanceInfo(String message, String availableAmount, String availableCashAmount, 
                                 String creditAmount, String currency) {
            this.message = message;
            this.availableAmount = availableAmount;
            this.availableCashAmount = availableCashAmount;
            this.creditAmount = creditAmount;
            this.currency = currency;
        }

        public String getMessage() {
            return message;
        }

        public void setMessage(String message) {
            this.message = message;
        }

        public String getAvailableAmount() {
            return availableAmount;
        }

        public void setAvailableAmount(String availableAmount) {
            this.availableAmount = availableAmount;
        }

        public String getAvailableCashAmount() {
            return availableCashAmount;
        }

        public void setAvailableCashAmount(String availableCashAmount) {
            this.availableCashAmount = availableCashAmount;
        }

        public String getCreditAmount() {
            return creditAmount;
        }

        public void setCreditAmount(String creditAmount) {
            this.creditAmount = creditAmount;
        }

        public String getCurrency() {
            return currency;
        }

        public void setCurrency(String currency) {
            this.currency = currency;
        }
    }
}

