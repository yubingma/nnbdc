package beidanci.service.util;

import java.util.HashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.aliyuncs.CommonRequest;
import com.aliyuncs.CommonResponse;
import com.aliyuncs.DefaultAcsClient;
import com.aliyuncs.IAcsClient;
import com.aliyuncs.exceptions.ClientException;
import com.aliyuncs.http.MethodType;
import com.aliyuncs.profile.DefaultProfile;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import beidanci.service.config.AliyunEmailProperties;

/**
 * 阿里云邮件推送服务工具类
 */
@Component
public class EmailUtil {

    private static final Logger logger = LoggerFactory.getLogger(EmailUtil.class);

    @Autowired
    private AliyunEmailProperties properties;

    private IAcsClient client;
    
    private final ObjectMapper objectMapper = new ObjectMapper();

    private void initClient() {
        try {
            String accessKeyId = properties.getAccessKeyId();
            String accessKeySecret = properties.getAccessKeySecret();
            String regionId = properties.getRegionId();
            if (isBlank(accessKeyId) || isBlank(accessKeySecret)) {
                logger.error("阿里云邮件凭据未配置：请在 application.yml 中配置 aliyun.email.access-key-id/secret");
                client = null;
                return;
            }
            if (isBlank(regionId)) {
                regionId = "cn-hangzhou";
            }
            DefaultProfile profile = DefaultProfile.getProfile(regionId, accessKeyId, accessKeySecret);
            client = new DefaultAcsClient(profile);
        } catch (Exception e) {
            logger.error("初始化阿里云邮件客户端失败", e);
            client = null;
        }
    }

    private boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }

    /**
     * 发送邮件
     * @param toEmail 收件人邮箱
     * @param toName 收件人名称
     * @param subject 邮件主题
     * @param content 邮件内容（HTML格式）
     * @return 发送结果，"OK"表示成功，其他为错误信息
     */
    public String sendEmail(String toEmail, String toName, String subject, String content) {
        try {
            if (client == null) {
                initClient();
            }
            if (client == null) {
                return "Email client not initialized";
            }

            String fromAddress = properties.getFromAddress();
            String fromAlias = properties.getFromAlias();
            if (isBlank(fromAddress)) {
                logger.error("发信地址未配置（aliyun.email.from-address 为空），已取消发送");
                return "From address not configured";
            }

            CommonRequest request = new CommonRequest();
            request.setSysMethod(MethodType.POST);
            request.setSysDomain("dm.aliyuncs.com");
            request.setSysVersion("2015-11-23");
            request.setSysAction("SingleSendMail");
            
            // 设置请求参数
            request.putQueryParameter("AccountName", fromAddress);
            if (!isBlank(fromAlias)) {
                request.putQueryParameter("FromAlias", fromAlias);
            }
            request.putQueryParameter("AddressType", "1"); // 1表示发信地址
            request.putQueryParameter("ToAddress", toEmail != null ? toEmail.trim() : "");
            request.putQueryParameter("Subject", subject);
            request.putQueryParameter("HtmlBody", content);
            request.putQueryParameter("ReplyToAddress", "false");

            CommonResponse response = client.getCommonResponse(request);
            JsonNode responseObj = objectMapper.readTree(response.getData());

            String requestId = responseObj.has("RequestId") ? responseObj.get("RequestId").asText() : null;
            if (requestId != null) {
                logger.info("邮件发送成功，收件人：{}，主题：{}，RequestId：{}", toEmail, subject, requestId);
                return "OK";
            } else {
                String errorMsg = responseObj.has("Message") ? responseObj.get("Message").asText() : "Unknown error";
                logger.error("邮件发送失败，收件人：{}，主题：{}，错误：{}", toEmail, subject, errorMsg);
                return errorMsg;
            }
        } catch (ClientException | JsonProcessingException e) {
            logger.error("邮件发送异常，收件人：{}，主题：{}", toEmail, subject, e);
            return e.getMessage();
        }
    }

    /**
     * 使用模板发送验证码邮件
     * @param toEmail 收件人邮箱
     * @param toName 收件人名称
     * @param code 验证码
     * @return 发送结果
     */
    public String sendVerificationCode(String toEmail, String toName, String code) {
        String templateId = properties.getTemplateIds().getVerificationCode();
        if (isBlank(templateId)) {
            logger.error("验证码模板ID未配置（aliyun.email.template-ids.verification-code 为空），已取消发送");
            return "Verification code template not configured";
        }
        // 使用 ObjectMapper 构建 JSON，确保格式正确
        try {
            Map<String, String> paramMap = new HashMap<>();
            paramMap.put("code", code);
            String templateParam = objectMapper.writeValueAsString(paramMap);
            logger.debug("发送验证码邮件，收件人：{}，模板：{}，参数：{}", toEmail, templateId, templateParam);
            return sendTemplatedEmail(toEmail, "邮箱验证码", templateId, templateParam);
        } catch (JsonProcessingException e) {
            logger.error("构建模板参数失败，收件人：{}，验证码：{}", toEmail, code, e);
            return "Failed to build template parameters: " + e.getMessage();
        }
    }

    /**
     * 使用模板发送获取密码邮件
     * @param toEmail 收件人邮箱
     * @param toName 收件人名称
     * @param password 用户密码
     * @return 发送结果
     */
    public String sendGetPasswordEmail(String toEmail, String toName, String password) {
        String templateId = properties.getTemplateIds().getGetPassword();
        if (isBlank(templateId)) {
            logger.error("获取密码模板ID未配置（aliyun.email.template-ids.get-password 为空），已取消发送");
            return "Get password template not configured";
        }
        // 使用 ObjectMapper 构建 JSON，确保格式正确
        // 模板变量名是 pwd，所以使用 pwd 作为参数名
        try {
            Map<String, String> paramMap = new HashMap<>();
            paramMap.put("pwd", password);
            String templateParam = objectMapper.writeValueAsString(paramMap);
            return sendTemplatedEmail(toEmail, "找回密码", templateId, templateParam);
        } catch (JsonProcessingException e) {
            logger.error("构建模板参数失败，收件人：{}", toEmail, e);
            return "Failed to build template parameters: " + e.getMessage();
        }
    }

    /**
     * 使用模板发送邮件
     * @param toEmail 收件人邮箱
     * @param toName 收件人名称
     * @param subject 邮件主题
     * @param templateId 模板ID
     * @param templateParam 模板参数（JSON格式）
     * @return 发送结果
     */
    @SuppressWarnings("unchecked")
    private String sendTemplatedEmail(String toEmail, String subject, String templateId, String templateParam) {
        try {
            if (client == null) {
                initClient();
            }
            if (client == null) {
                return "Email client not initialized";
            }

            String fromAddress = properties.getFromAddress();
            String fromAlias = properties.getFromAlias();
            if (isBlank(fromAddress)) {
                logger.error("发信地址未配置（aliyun.email.from-address 为空），已取消发送");
                return "From address not configured";
            }

            CommonRequest request = new CommonRequest();
            request.setSysMethod(MethodType.POST);
            request.setSysDomain("dm.aliyuncs.com");
            request.setSysVersion("2015-11-23");
            request.setSysAction("SingleSendMail");
            
            // 确保 TemplateParam 是有效的 JSON 字符串
            String finalTemplateParam = templateParam;
            if (finalTemplateParam == null || finalTemplateParam.trim().isEmpty()) {
                finalTemplateParam = "{}";
            }
            
            // Subject 参数是必需的
            String finalSubject = isBlank(subject) ? "邮件通知" : subject;
            
            // 设置请求参数
            request.putQueryParameter("AccountName", fromAddress);
            if (!isBlank(fromAlias)) {
                request.putQueryParameter("FromAlias", fromAlias);
            }
            request.putQueryParameter("AddressType", "1"); // 1表示发信地址
            request.putQueryParameter("ToAddress", toEmail != null ? toEmail.trim() : "");
            request.putQueryParameter("Subject", finalSubject);
            
            // 使用模板发送邮件时，恢复之前的 Template JSON 结构
            try {
                Map<String, Object> templateMap = new HashMap<>();
                templateMap.put("TemplateId", templateId);
                // TemplateData 需要是对象，将 JSON 字符串解析为对象
                Map<String, Object> templateDataMap = objectMapper.readValue(finalTemplateParam, Map.class);
                templateMap.put("TemplateData", templateDataMap);
                String templateJson = objectMapper.writeValueAsString(templateMap);
                request.putQueryParameter("Template", templateJson);
            } catch (JsonProcessingException e) {
                logger.error("构建 Template 参数失败: {}", e.getMessage(), e);
                return "Failed to build Template parameter: " + e.getMessage();
            }
            
            request.putQueryParameter("ReplyToAddress", "false");
            
            logger.info("发送模板邮件请求，收件人：{}，模板：{}，参数：{}，主题：{}", 
                toEmail, templateId, finalTemplateParam, finalSubject);

            CommonResponse response = client.getCommonResponse(request);
            JsonNode responseObj = objectMapper.readTree(response.getData());

            String requestId = responseObj.has("RequestId") ? responseObj.get("RequestId").asText() : null;
            if (requestId != null) {
                logger.info("模板邮件发送成功，收件人：{}，模板：{}，RequestId：{}", toEmail, templateId, requestId);
                return "OK";
            } else {
                String errorMsg = responseObj.has("Message") ? responseObj.get("Message").asText() : "Unknown error";
                logger.error("模板邮件发送失败，收件人：{}，模板：{}，错误：{}", toEmail, templateId, errorMsg);
                return errorMsg;
            }
        } catch (ClientException | JsonProcessingException e) {
            logger.error("模板邮件发送异常，收件人：{}，模板：{}", toEmail, templateId, e);
            return e.getMessage();
        }
    }
}
