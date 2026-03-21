package beidanci.service.bo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import com.alibaba.dashscope.aigc.generation.Generation;
import com.alibaba.dashscope.aigc.generation.GenerationParam;
import com.alibaba.dashscope.aigc.generation.GenerationResult;
import com.alibaba.dashscope.aigc.imagesynthesis.ImageSynthesis;
import com.alibaba.dashscope.aigc.imagesynthesis.ImageSynthesisParam;
import com.alibaba.dashscope.aigc.imagesynthesis.ImageSynthesisResult;
import com.alibaba.dashscope.common.Message;
import com.alibaba.dashscope.common.Role;
import com.alibaba.dashscope.exception.InputRequiredException;
import com.alibaba.dashscope.exception.NoApiKeyException;
import com.alibaba.dashscope.audio.tts.SpeechSynthesisParam;
import com.alibaba.dashscope.audio.tts.SpeechSynthesizer;
import java.nio.ByteBuffer;

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
        String[] voices = {"longanyang", "longfei", "longzhe", "longanhuan", "longwan", "longfeifei"};
        String voice = voices[new java.util.Random().nextInt(voices.length)];
        
        try {
            return callCosyVoice(text, voice);
        } catch (Exception e) {
            String defaultVoice = aiProperties.getVoice();
            logger.warn("随机音色 {} 合成失败(可能是音色不存在)，尝试回退到保底音色: {}", voice, defaultVoice, e);
            if (!voice.equals(defaultVoice)) {
                try {
                    return callCosyVoice(text, defaultVoice);
                } catch (Exception fallbackEx) {
                    throw new RuntimeException("保底 TTS 系统异常", fallbackEx);
                }
            }
            throw new RuntimeException("TTS 系统异常", e);
        }
    }

    private byte[] callCosyVoice(String text, String voice) throws Exception {
        logger.info("请求语音合成: [模型: {}, 发音人: {}] 内容: {}", 
                   aiProperties.getTtsModel(), voice, text);
        
        String apiKey = aiProperties.getApiKey();
        if (apiKey == null || apiKey.isEmpty() || apiKey.startsWith("${")) {
            logger.error("阿里云 AI 调用失败: API Key 未设置或未正确解析");
            throw new RuntimeException("AI 调用失败: 请设置 dashscope_api_key");
        }

        SpeechSynthesizer synthesizer = new SpeechSynthesizer();
        SpeechSynthesisParam param = SpeechSynthesisParam.builder()
                .apiKey(apiKey)
                .model(aiProperties.getTtsModel())
                .parameter("voice", voice)
                .parameter("format", "mp3")
                .text(text)
                .build();
        
        ByteBuffer buffer = synthesizer.call(param);
        byte[] audioBytes = new byte[buffer.remaining()];
        buffer.get(audioBytes);
        
        return audioBytes;
    }

    /**
     * 调用阿里云 WanX 模型生成图片。
     * @param prompt 提示词
     * @return 图片下载链接，失败返回null
     */
    public String generateImage(String prompt) {
        String apiKey = aiProperties.getApiKey();
        if (apiKey == null || apiKey.isEmpty() || apiKey.startsWith("${")) {
            logger.warn("未配置DashScope API Key，跳过图片生成。");
            return null;
        }
        try {
            logger.info("请求图片生成: [模型: wanx-v1] 提示词: {}", prompt);
            ImageSynthesis is = new ImageSynthesis();
            ImageSynthesisParam param = ImageSynthesisParam.builder()
                    .apiKey(apiKey)
                    .model("wanx-v1")
                    .prompt(prompt)
                    .n(1)
                    .size("1024*1024")
                    .build();
            ImageSynthesisResult result = is.call(param);
            if (result != null && result.getOutput() != null && result.getOutput().getResults() != null && !result.getOutput().getResults().isEmpty()) {
                String url = result.getOutput().getResults().get(0).get("url");
                logger.info("图片生成成功: {}", url);
                return url;
            }
        } catch (Exception e) {
            logger.error("生成图片失败: " + prompt, e);
        }
        return null;
    }

    /**
     * 调用视觉大模型进行配图审核
     * @param wordSpell 对应的单词
     * @param absoluteImagePath 图片的绝对路径
     * @return 包含 {"action": "DELETE", "reason": "xxx"} 或 {"action": "KEEP"} 的 JSON 字符串
     */
    public String reviewImage(String wordSpell, String absoluteImagePath) {
        String apiKey = aiProperties.getApiKey();
        if (apiKey == null || apiKey.isEmpty() || apiKey.startsWith("${")) return "{\"action\":\"KEEP\"}";
        try {
            logger.info("开始审图: word={}, path={}", wordSpell, absoluteImagePath);
            Object conv = Class.forName("com.alibaba.dashscope.aigc.multimodalconversation.MultiModalConversation").getDeclaredConstructor().newInstance();
            
            java.util.Map<String, Object> imgMap = new java.util.HashMap<>();
            imgMap.put("image", "file://" + absoluteImagePath);
            java.util.Map<String, Object> txtMap = new java.util.HashMap<>();
            txtMap.put("text", "你是一位严苛的英文单词教学配图审核专家。请仔细查看这张被用来作为英文单词【" + wordSpell + "】配图的图片。\n" + 
                "只要出现以下任何一种情况，请坚决鉴定为不合格：\n" + 
                "1. 图片主要内容是与单词拼写相同的商业商标（Logo）、品牌产品（如单词是apple却画了苹果公司的标志或手机），这对于学习单词的本意毫无意义。\n" + 
                "2. 图片出现了任何色情、擦边、性暗示或是衣着极为暴露的成人内容，这种图绝对不能用来学习单词。\n" + 
                "3. 图片内部明显出现了任何英文字母文本、单词拼写、单词释义、水印或突兀的UI符号。\n" + 
                "4. 画面内容与单词的字面普适含义毫无关联，或者是生硬且不知所云的拼凑画面。\n" + 
                "5. 该单词属于人名、非常纯粹的抽象哲学概念、或缺乏画面的语法虚词，却遭到了毫无意义的强行配图。\n" +
                "请严格只返回没有任何Markdown格式标注的纯 JSON 对象，格式为：{\"action\":\"DELETE\",\"reason\":\"具体不合格的原因\"}，如果审核通过，则返回 {\"action\":\"KEEP\"}。");
                
            com.alibaba.dashscope.common.MultiModalMessage userMessage = com.alibaba.dashscope.common.MultiModalMessage.builder()
                .role(com.alibaba.dashscope.common.Role.USER.getValue())
                .content(java.util.Arrays.asList(imgMap, txtMap))
                .build();
                
            com.alibaba.dashscope.aigc.multimodalconversation.MultiModalConversationParam param = com.alibaba.dashscope.aigc.multimodalconversation.MultiModalConversationParam.builder()
                .apiKey(apiKey)
                .model("qwen-vl-plus")
                .message(userMessage)
                .build();
                
            java.lang.reflect.Method callMethod = conv.getClass().getMethod("call", com.alibaba.dashscope.aigc.multimodalconversation.MultiModalConversationParam.class);
            Object result = callMethod.invoke(conv, param);
            
            java.lang.reflect.Method getOutputMethod = result.getClass().getMethod("getOutput");
            Object output = getOutputMethod.invoke(result);
            
            java.lang.reflect.Method getChoicesMethod = output.getClass().getMethod("getChoices");
            java.util.List<?> choices = (java.util.List<?>) getChoicesMethod.invoke(output);
            
            Object choice = choices.get(0);
            java.lang.reflect.Method getMessageMethod = choice.getClass().getMethod("getMessage");
            Object message = getMessageMethod.invoke(choice);
            
            java.lang.reflect.Method getContentMethod = message.getClass().getMethod("getContent");
            java.util.List<?> contentList = (java.util.List<?>) getContentMethod.invoke(message);
            
            java.util.Map<?, ?> contentMap = (java.util.Map<?, ?>) contentList.get(0);
            String jsonResult = (String) contentMap.get("text");
            
            logger.info("审图结果: " + jsonResult);
            return jsonResult;
        } catch (Exception e) {
            logger.error("审图异常: " + absoluteImagePath, e);
            return "{\"action\":\"KEEP\"}";
        }
    }
}
