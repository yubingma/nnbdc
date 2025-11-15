package beidanci.service.util;

import java.util.HashMap;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * EmailUtil JSON 构建测试
 * 独立单元测试，不依赖 Spring 上下文和数据库
 */
public class EmailUtilJsonTest {

    private static final Logger logger = LoggerFactory.getLogger(EmailUtilJsonTest.class);
    
    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * 测试 JSON 参数构建
     */
    @Test
    @DisplayName("测试模板参数 JSON 格式构建")
    public void testTemplateParamJson() throws Exception {
        logger.info("=== 开始测试模板参数 JSON 格式 ===");
        
        // 测试验证码参数
        Map<String, String> codeMap = new HashMap<>();
        codeMap.put("code", "123456");
        String codeJson = objectMapper.writeValueAsString(codeMap);
        logger.info("验证码参数 JSON: {}", codeJson);
        
        // 验证 JSON 格式正确
        JsonNode node1 = objectMapper.readTree(codeJson);
        assert node1.has("code") : "JSON 缺少 code 字段";
        assert "123456".equals(node1.get("code").asText()) : "code 值不正确";
        logger.info("✓ 验证码参数 JSON 格式正确");
        
        // 测试包含特殊字符的验证码
        codeMap.put("code", "test\"code");
        String codeJson2 = objectMapper.writeValueAsString(codeMap);
        logger.info("包含特殊字符的验证码参数 JSON: {}", codeJson2);
        
        JsonNode node2 = objectMapper.readTree(codeJson2);
        assert node2.has("code") : "JSON 缺少 code 字段";
        assert "test\"code".equals(node2.get("code").asText()) : "包含引号的 code 值不正确";
        logger.info("✓ 包含特殊字符的验证码参数 JSON 格式正确");
        
        // 测试密码内容参数
        Map<String, String> contentMap = new HashMap<>();
        contentMap.put("content", "您的密码是：123456");
        String contentJson = objectMapper.writeValueAsString(contentMap);
        logger.info("密码内容参数 JSON: {}", contentJson);
        
        JsonNode node3 = objectMapper.readTree(contentJson);
        assert node3.has("content") : "JSON 缺少 content 字段";
        assert "您的密码是：123456".equals(node3.get("content").asText()) : "content 值不正确";
        logger.info("✓ 密码内容参数 JSON 格式正确");
        
        logger.info("=== 所有 JSON 格式测试通过 ===");
    }

    /**
     * 测试验证码参数构建逻辑
     */
    @Test
    @DisplayName("测试各种验证码参数构建")
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
            
            logger.info("验证码: [{}] -> JSON: {}", code, templateParam);
            
            // 验证 JSON 可以正常解析
            Map<?, ?> parsed = objectMapper.readValue(templateParam, Map.class);
            String parsedCode = (String) parsed.get("code");
            
            if (code.equals(parsedCode)) {
                logger.info("  ✓ JSON 解析成功，值匹配");
            } else {
                logger.error("  ✗ JSON 解析后值不匹配: 原值=[{}], 解析值=[{}]", code, parsedCode);
                throw new AssertionError(String.format("JSON 解析后值不匹配: 原值=[%s], 解析值=[%s]", code, parsedCode));
            }
        }
        
        logger.info("=== 所有验证码参数构建测试通过 ===");
    }
    
    /**
     * 测试模拟实际发送验证码的参数构建
     */
    @Test
    @DisplayName("模拟实际发送验证码的参数构建")
    public void testSimulateSendVerificationCode() throws Exception {
        logger.info("=== 模拟实际发送验证码的参数构建 ===");
        
        // 模拟 EmailUtil.sendVerificationCode 方法的参数构建逻辑
        String toEmail = "mmyybb3000@icloud.com";
        String toName = "用户";
        String code = "123456";
        String templateId = "417522";
        String subject = "邮箱验证码";
        
        // 使用 ObjectMapper 构建 JSON（与实际代码相同）
        Map<String, String> paramMap = new HashMap<>();
        paramMap.put("code", code);
        String templateParam = objectMapper.writeValueAsString(paramMap);
        
        logger.info("模拟发送验证码邮件:");
        logger.info("  收件人: {}", toEmail);
        logger.info("  收件人名称: {}", toName);
        logger.info("  验证码: {}", code);
        logger.info("  模板ID: {}", templateId);
        logger.info("  主题: {}", subject);
        logger.info("  模板参数 JSON: {}", templateParam);
        
        // 验证 JSON 格式
        JsonNode jsonNode = objectMapper.readTree(templateParam);
        assert jsonNode.has("code") : "模板参数 JSON 缺少 code 字段";
        assert code.equals(jsonNode.get("code").asText()) : "模板参数 JSON 的 code 值不正确";
        
        // 模拟构建请求参数（用于调试）
        logger.info("模拟请求参数:");
        logger.info("  AccountName: [需要从配置读取]");
        logger.info("  AddressType: 1");
        logger.info("  ToAddress: {}", toEmail);
        logger.info("  Subject: {}", subject);
        logger.info("  TemplateCode: {}", templateId);
        logger.info("  TemplateParam: {}", templateParam);
        logger.info("  ReplyToAddress: false");
        logger.info("  HtmlBody: [未设置]");
        logger.info("  TextBody: [未设置]");
        
        logger.info("✓ 模拟参数构建成功");
        logger.info("=== 模拟测试完成 ===");
    }
}

