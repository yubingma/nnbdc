package beidanci.service.bo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import com.alibaba.dashscope.aigc.generation.Generation;
import com.alibaba.dashscope.aigc.generation.GenerationParam;
import com.alibaba.dashscope.aigc.generation.GenerationResult;
import com.alibaba.dashscope.common.Message;
import com.alibaba.dashscope.common.Role;
import com.alibaba.dashscope.exception.InputRequiredException;
import com.alibaba.dashscope.exception.NoApiKeyException;

import beidanci.service.config.AliyunAiProperties;

import java.util.Arrays;

/**
 * 阿里云 AI 业务类
 * 处理文本生成 (Qwen) 和 语音合成 (CosyVoice)
 */
@Service
public class AiBo {

    private static final Logger logger = LoggerFactory.getLogger(AiBo.class);

    @Autowired
    private AliyunAiProperties aiProperties;

    /**
     * 调用通义千问产生文本结果
     *
     * @param systemPrompt 系统角色设定
     * @param userPrompt   用户输入内容
     * @return AI 生成的文本
     */
    public String generateText(String systemPrompt, String userPrompt) {
        String apiKey = aiProperties.getApiKey();
        if (apiKey == null || apiKey.isEmpty() || apiKey.startsWith("${")) {
            logger.error("阿里云 AI 调用失败: API Key 未设置或未正确解析 (当前值为: {})", apiKey);
            throw new RuntimeException("AI 调用失败: 请在环境变量或配置文件中设置 dashscope_api_key");
        }

        try {
            Generation gen = new Generation();
            Message systemMsg = Message.builder()
                    .role(Role.SYSTEM.getValue())
                    .content(systemPrompt)
                    .build();
            Message userMsg = Message.builder()
                    .role(Role.USER.getValue())
                    .content(userPrompt)
                    .build();
            GenerationParam param = GenerationParam.builder()
                    .apiKey(apiKey)
                    .model(aiProperties.getTextModel())
                    .messages(Arrays.asList(systemMsg, userMsg))
                    .resultFormat(GenerationParam.ResultFormat.MESSAGE)
                    .build();
            GenerationResult result = gen.call(param);
            return result.getOutput().getChoices().get(0).getMessage().getContent();
        } catch (NoApiKeyException | InputRequiredException e) {
            logger.error("阿里云 AI 调用失败: 缺少 API Key 或输入错误", e);
            throw new RuntimeException("AI 调用失败", e);
        } catch (Exception e) {
            logger.error("阿里云 AI 调用发生未知异常", e);
            throw new RuntimeException("AI 系统异常", e);
        }
    }

    /**
     * 语音合成 (TTS) - 采用阿里云 CosyVoice
     * 产生的音频文件通常应保存到 /var/www/html/sound 目录下，以便前端访问
     *
     * @param text 需要合成的文本
     * @return 合成后的音频字节流
     */
    public byte[] generateSpeech(String text) {
        logger.info("请求语音合成: [模型: {}, 发音人: {}] 内容: {}", 
                   aiProperties.getTtsModel(), aiProperties.getVoice(), text);
        // 实现参考：
        // 1. 使用 SpeechSynthesizer (DashScope SDK)
        // 2. 设置 apiKey, model, voice, format (mp3)
        // 3. 调用 call() 并获取 binary data
        
        // 此处暂存占位，后续根据实际音频存储路径需求（如 OSS 或本地 CDN）接入完整流程
        return new byte[0]; 
    }
}
