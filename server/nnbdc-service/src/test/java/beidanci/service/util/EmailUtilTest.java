package beidanci.service.util;

import java.util.HashMap;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import beidanci.service.config.AliyunEmailProperties;

/**
 * EmailUtil 测试类
 * 用于验证邮件发送功能，特别是模板邮件发送
 */
@SpringBootTest
@ActiveProfiles("test")
public class EmailUtilTest {

    private static final Logger logger = LoggerFactory.getLogger(EmailUtilTest.class);
    
    @Autowired(required = false)
    private EmailUtil emailUtil;
    
    @Autowired(required = false)
    private AliyunEmailProperties properties;
    
    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * 测试 JSON 参数构建
     */
    @Test
    @DisplayName("测试模板参数 JSON 格式")
    public void testTemplateParamJson() throws Exception {
        logger.info("=== 开始测试模板参数 JSON 格式 ===");
        
        // 测试验证码参数
        Map<String, String> codeMap = new HashMap<>();
        codeMap.put("code", "123456");
        String codeJson = objectMapper.writeValueAsString(codeMap);
        logger.info("验证码参数 JSON: {}", codeJson);
        
        // 测试包含特殊字符的验证码
        codeMap.put("code", "test\"code");
        String codeJson2 = objectMapper.writeValueAsString(codeMap);
        logger.info("包含特殊字符的验证码参数 JSON: {}", codeJson2);
        
        // 测试密码内容参数
        Map<String, String> contentMap = new HashMap<>();
        contentMap.put("content", "您的密码是：123456");
        String contentJson = objectMapper.writeValueAsString(contentMap);
        logger.info("密码内容参数 JSON: {}", contentJson);
        
        // 验证 JSON 格式
        JsonNode node1 = objectMapper.readTree(codeJson);
        JsonNode node2 = objectMapper.readTree(contentJson);
        logger.info("JSON 格式验证通过 - code节点: {}, content节点: {}", 
            node1.has("code") ? node1.get("code").asText() : "missing", 
            node2.has("content") ? node2.get("content").asText() : "missing");
        
        logger.info("=== 测试完成 ===");
    }

    /**
     * 测试发送验证码邮件（实际发送，需要配置）
     * 注意：此测试需要真实的阿里云配置，仅在需要时启用
     */
    @Test
    @DisplayName("测试发送验证码邮件")
    public void testSendVerificationCode() {
        if (emailUtil == null || properties == null) {
            logger.warn("EmailUtil 或 AliyunEmailProperties 未注入，跳过实际发送测试");
            logger.warn("如需测试，请确保配置了 aliyun.email 相关参数");
            return;
        }
        
        String templateId = properties.getTemplateIds().getVerificationCode();
        if (templateId == null || templateId.trim().isEmpty()) {
            logger.warn("验证码模板ID未配置，跳过实际发送测试");
            return;
        }
        
        logger.info("=== 开始测试发送验证码邮件 ===");
        logger.info("模板ID: {}", templateId);
        logger.info("发信地址: {}", properties.getFromAddress());
        
        // 使用测试邮箱（请替换为您的测试邮箱）
        String testEmail = "test@example.com"; // 请修改为实际测试邮箱
        String testCode = "123456";
        String toName = "测试用户";
        
        logger.info("准备发送验证码邮件到: {}", testEmail);
        String result = emailUtil.sendVerificationCode(testEmail, toName, testCode);
        
        logger.info("发送结果: {}", result);
        
        if ("OK".equals(result)) {
            logger.info("✓ 邮件发送成功");
        } else {
            logger.error("✗ 邮件发送失败: {}", result);
        }
        
        logger.info("=== 测试完成 ===");
    }

    /**
     * 测试验证码参数构建逻辑
     */
    @Test
    @DisplayName("测试验证码参数构建逻辑")
    public void testBuildVerificationCodeParams() throws Exception {
        logger.info("=== 开始测试验证码参数构建逻辑 ===");
        
        String[] testCodes = {
            "123456",
            "000000",
            "999999",
            "012345",
            "abcdef",
            "test\"code",
            "test\\code",
            "test\ncode",
            "test\tcode"
        };
        
        for (String code : testCodes) {
            Map<String, String> paramMap = new HashMap<>();
            paramMap.put("code", code);
            String templateParam = objectMapper.writeValueAsString(paramMap);
            
            logger.info("验证码: {} -> JSON: {}", code, templateParam);
            
            // 验证 JSON 可以正常解析
            Map<?, ?> parsed = objectMapper.readValue(templateParam, Map.class);
            String parsedCode = (String) parsed.get("code");
            
            if (code.equals(parsedCode)) {
                logger.info("  ✓ JSON 解析成功，值匹配");
            } else {
                logger.error("  ✗ JSON 解析后值不匹配: 原值={}, 解析值={}", code, parsedCode);
            }
        }
        
        logger.info("=== 测试完成 ===");
    }
}

