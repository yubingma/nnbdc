package beidanci.service.util;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.aliyuncs.DefaultAcsClient;
import com.aliyuncs.IAcsClient;
import com.aliyuncs.dysmsapi.model.v20170525.SendSmsRequest;
import com.aliyuncs.dysmsapi.model.v20170525.SendSmsResponse;
import com.aliyuncs.exceptions.ClientException;
import com.aliyuncs.profile.DefaultProfile;

import beidanci.service.config.AliyunSmsProperties;

/**
 * 阿里云短信服务工具类
 */
@Component
public class SmsUtil {

    private static final Logger logger = LoggerFactory.getLogger(SmsUtil.class);

    @Autowired
    private AliyunSmsProperties properties;

    private IAcsClient client;

    private void initClient() {
        try {
            String accessKeyId = properties.getAccessKeyId();
            String accessKeySecret = properties.getAccessKeySecret();
            String regionId = properties.getRegionId();
            if (isBlank(accessKeyId) || isBlank(accessKeySecret)) {
                logger.error("阿里云短信凭据未配置：请在 application-sms.yml 中配置 aliyun.sms.access-key-id/secret");
                client = null;
                return;
            }
            if (isBlank(regionId)) {
                regionId = "cn-hangzhou";
            }
            DefaultProfile profile = DefaultProfile.getProfile(regionId, accessKeyId, accessKeySecret);
            client = new DefaultAcsClient(profile);
        } catch (Exception e) {
            logger.error("初始化阿里云短信客户端失败", e);
            client = null;
        }
    }

    private boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }

    /**
     * 发送短信
     * @param phoneNumber 手机号
     * @param templateCode 模板代码
     * @param templateParam 模板参数（JSON格式）
     * @return 发送结果
     */
    public String sendSms(String phoneNumber, String templateCode, String templateParam) {
        try {
            if (client == null) {
                initClient();
            }
            if (client == null) {
                return "SMS client not initialized";
            }
            SendSmsRequest request = new SendSmsRequest();
            request.setPhoneNumbers(phoneNumber);
            String signName = properties.getSignName();
            if (isBlank(signName)) {
                logger.error("短信签名未配置（aliyun.sms.sign-name 为空），已取消发送");
                return "SMS sign-name not configured";
            }
            request.setSignName(signName);
            request.setTemplateCode(templateCode);
            request.setTemplateParam(templateParam);

            SendSmsResponse response = client.getAcsResponse(request);

            if ("OK".equals(response.getCode())) {
                logger.info("短信发送成功，手机号：{}，模板：{}", phoneNumber, templateCode);
                return "OK";
            } else {
                logger.error("短信发送失败，手机号：{}，模板：{}，错误：{}", phoneNumber, templateCode, response.getMessage());
                return response.getMessage();
            }
        } catch (ClientException e) {
            logger.error("短信发送异常，手机号：{}，模板：{}", phoneNumber, templateCode, e);
            return e.getMessage();
        }
    }

    /**
     * 发送验证码短信
     * @param phoneNumber 手机号
     * @param code 验证码
     * @param templateCode 模板代码
     * @return 发送结果
     */
    public String sendVerificationCode(String phoneNumber, String code, String templateCode) {
        String templateParam = "{\"code\":\"" + code + "\"}";
        return sendSms(phoneNumber, templateCode, templateParam);
    }
}
