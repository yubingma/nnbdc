package beidanci.service.bo;

import beidanci.api.Result;

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
import io.reactivex.Flowable;
import com.alibaba.dashscope.audio.tts.SpeechSynthesizer;
import java.nio.ByteBuffer;
import org.springframework.http.*;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.client.OkHttp3ClientHttpRequestFactory;
import org.springframework.core.io.FileSystemResource;
import java.io.File;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.lang.reflect.Method;

import org.springframework.scheduling.annotation.Scheduled;
import beidanci.service.config.AliyunAiProperties;
import beidanci.service.util.SysParamUtil;

/**
 * 阿里云 AI 业务类
 * 处理文本生成 (Qwen) 和 语音合成 (CosyVoice)
 */
@Service
public class AiBo {

    private static final Logger logger = LoggerFactory.getLogger(AiBo.class);

    @Autowired
    private AliyunAiProperties aiProperties;

    @Autowired
    private SysParamUtil sysParamUtil;

    private final AtomicInteger activeAiStoryRequests = new AtomicInteger(0);
    private final AtomicInteger activeAiChatRequests = new AtomicInteger(0);
    private final ConcurrentHashMap<String, AtomicInteger> userAiChatRequests = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, AtomicInteger> userDailyAiChatRequests = new ConcurrentHashMap<>();

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
     * 调用通义千问进行多轮对话
     *
     * @param messages 用户和系统消息列表
     * @return AI 生成的文本
     */
    public String chat(List<Message> messages) {
        String apiKey = aiProperties.getApiKey();
        if (apiKey == null || apiKey.isEmpty() || apiKey.startsWith("${")) {
            logger.error("阿里云 AI 调用失败: API Key 未设置或未正确解析");
            throw new RuntimeException("AI 调用失败: 请在环境变量或配置文件中设置 dashscope_api_key");
        }

        try {
            Generation gen = new Generation();
            GenerationParam param = GenerationParam.builder()
                    .apiKey(apiKey)
                    .model("qwen-plus") // 或者使用 aiProperties.getTextModel()，在此场景中 qwen-plus 最合适
                    .messages(messages)
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
     * 进入 AI 聊天计数 (并发限制)
     * @param userId 用户 ID
     * @param userIdentifier 用户标识 (用于日志，如 "昵称(ID)")
     * @param clientType 客户端类型 (如 "iOS", "Android", "Web")
     * @return AI 聊天资源进入结果 (成功则包含释放资源的 Runnable)
     */
    public Result<Runnable> enterAiChat(String userId, String userIdentifier, String clientType) {
        int globalLimit = sysParamUtil.getAiChatGlobalLimit();
        int userLimit = sysParamUtil.getAiChatUserLimit();
        int userDailyLimit = sysParamUtil.getAiChatUserDailyLimit();

        if (activeAiChatRequests.get() >= globalLimit) {
            logger.warn("AI 全局并发达到上限: {}", globalLimit);
            return Result.fail("服务器 AI 服务并发达到上限，请稍后再试");
        }

        AtomicInteger userCount = userAiChatRequests.computeIfAbsent(userId, k -> new AtomicInteger(0));
        if (userCount.get() >= userLimit) {
            logger.warn("AI 用户并发达到上限: {}", userLimit);
            return Result.fail("您的 AI 聊天并发请求过多，请等待上一个回复结束");
        }

        AtomicInteger userDailyCount = userDailyAiChatRequests.computeIfAbsent(userId, k -> new AtomicInteger(0));
        if (userDailyCount.get() >= userDailyLimit) {
            logger.warn("今日 AI 聊天次数达到上限: {}", userDailyLimit);
            return Result.fail("您今日的 AI 聊天次数已达到上限 (" + userDailyLimit + "次)，请明天再试");
        }

        activeAiChatRequests.incrementAndGet();
        userCount.incrementAndGet();
        userDailyCount.incrementAndGet();

        return Result.success(null, () -> {
            activeAiChatRequests.decrementAndGet();
            userCount.decrementAndGet();
        });
    }

    /**
     * 每日凌晨清空用户调用计数 (流控重置)
     */
    @Scheduled(cron = "0 0 0 * * ?")
    public void resetDailyStats() {
        logger.info("重置用户 AI 聊天每日调用计数");
        userDailyAiChatRequests.clear();
    }

    /**
     * 调用通义千问进行多轮对话 (流式输出)
     *
     * @param messages 用户和系统消息列表
     * @return AI 生成的文本结果流
     */
    public Flowable<GenerationResult> chatStream(List<Message> messages) {
        String apiKey = aiProperties.getApiKey();
        if (apiKey == null || apiKey.isEmpty() || apiKey.startsWith("${")) {
            logger.error("阿里云 AI 调用失败: API Key 未设置或未正确解析");
            throw new RuntimeException("AI 调用失败: 请在环境变量或配置文件中设置 dashscope_api_key");
        }

        try {
            Generation gen = new Generation();
            GenerationParam param = GenerationParam.builder()
                    .apiKey(apiKey)
                    .model("qwen-plus")
                    .messages(messages)
                    .resultFormat(GenerationParam.ResultFormat.MESSAGE)
                    .incrementalOutput(true)
                    .build();
            return gen.streamCall(param);
        } catch (NoApiKeyException | InputRequiredException e) {
            logger.error("阿里云 AI 调用失败: 缺少 API Key 或输入错误", e);
            throw new RuntimeException("AI 调用失败", e);
        } catch (Exception e) {
            logger.error("阿里云 AI 调用发生未知异常", e);
            throw new RuntimeException("AI 系统异常", e);
        }
    }

    public int getStoryConcurrencyLimit() {
        return sysParamUtil.getAiStoryConcurrencyLimit();
    }

    public static class TtsResult {
        public byte[] audioData;
        public String voice;
        public String engine;

        public TtsResult(byte[] audioData, String voice, String engine) {
            this.audioData = audioData;
            this.voice = voice;
            this.engine = engine;
        }
    }

    /**
     * 语音合成 (TTS) - 采用阿里云 CosyVoice
     * 产生的音频文件通常应保存到 /var/www/html/sound 目录下，以便前端访问
     *
     * @param text 需要合成的文本
     * @param voiceInstruction 音效/风格指令
     * @return 合成后的音频信息和字节流
     */
    public TtsResult generateSpeech(String text, String preferredVoicesStr, String voiceInstruction) {
        String[] voices = {"longanyang", "longanhuan", "longxiaochun_v3", "longxiaoxia_v3", "longniuniu_v3", "longhuhu_v3", "longjielidou_v3"};
        if (preferredVoicesStr != null && !preferredVoicesStr.trim().isEmpty()) {
            voices = preferredVoicesStr.split(",");
            for (int i = 0; i < voices.length; i++) voices[i] = voices[i].trim();
        }
        String voice = voices[new Random().nextInt(voices.length)];
        
        try {
            return new TtsResult(callCosyVoice(text, voice, voiceInstruction), voice, aiProperties.getTtsModel());
        } catch (Exception e) {
            String defaultVoice = voices[0];
            logger.warn("随机音色 {} 合成失败(可能是音色不存在)，尝试回退到用户首选/兜底音色: {}", voice, defaultVoice, e);
            if (!voice.equals(defaultVoice)) {
                try {
                    return new TtsResult(callCosyVoice(text, defaultVoice, voiceInstruction), defaultVoice, aiProperties.getTtsModel());
                } catch (Exception fallbackEx) {
                    logger.warn("首选音色也失败了，最后尝试系统全局保底音色: {}", aiProperties.getVoice());
                    try {
                        return new TtsResult(callCosyVoice(text, aiProperties.getVoice(), voiceInstruction), aiProperties.getVoice(), aiProperties.getTtsModel());
                    } catch (Exception ext) {
                        throw new RuntimeException("保底 TTS 系统异常", ext);
                    }
                }
            } else if (!voice.equals(aiProperties.getVoice())) {
                try {
                    return new TtsResult(callCosyVoice(text, aiProperties.getVoice(), voiceInstruction), aiProperties.getVoice(), aiProperties.getTtsModel());
                } catch (Exception fallbackEx) {
                    throw new RuntimeException("保底 TTS 系统异常", fallbackEx);
                }
            }
            throw new RuntimeException("TTS 系统异常", e);
        }
    }

    private byte[] callCosyVoice(String text, String voice, String voiceInstruction) throws Exception {
        logger.info("请求语音合成: [模型: {}, 发音人: {}, 指令: {}] 内容: {}", 
                   aiProperties.getTtsModel(), voice, voiceInstruction, text);
        
        String apiKey = aiProperties.getApiKey();
        if (apiKey == null || apiKey.isEmpty() || apiKey.startsWith("${")) {
            logger.error("阿里云 AI 调用失败: API Key 未设置或未正确解析");
            throw new RuntimeException("AI 调用失败: 请设置 dashscope_api_key");
        }

        SpeechSynthesizer synthesizer = new SpeechSynthesizer();
        var paramBuilder = SpeechSynthesisParam.builder()
                .apiKey(apiKey)
                .model(aiProperties.getTtsModel())
                .parameter("voice", voice)
                .parameter("format", "mp3")
                .text(text);
        
        if (voiceInstruction != null && !voiceInstruction.trim().isEmpty()) {
            // 目前仅部分带有 -instruct 后缀的模型支持 instruction 参数。
            // 对于不支持的模型，我们将捕获 ApiException 并进行自动降级。
            paramBuilder.parameter("instruction", voiceInstruction);
        }
        
        SpeechSynthesisParam param = (SpeechSynthesisParam) paramBuilder.build();
        
        ByteBuffer buffer;
        try {
            buffer = synthesizer.call(param);
        } catch (com.alibaba.dashscope.exception.ApiException e) {
            // 特别处理：如果错误代码为 428 (InvalidParameter)，通常意味着模型不支持 instruction 或其它特定参数
            if (e.getMessage().contains("428") && voiceInstruction != null) {
                logger.warn("当前 TTS 模型 [{}] 不支持语气指令 [{}], 尝试剥离指令进行降级合成。详情: {}", 
                           aiProperties.getTtsModel(), voiceInstruction, e.getMessage());
                paramBuilder.parameter("instruction", null);
                param = (SpeechSynthesisParam) paramBuilder.build();
                buffer = synthesizer.call(param);
            } else {
                throw e;
            }
        }
        
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
            
            // 万相大模型等需要标准文件 URL，若路径含空格需进行显式转义
            String safePath = absoluteImagePath.replace(" ", "%20");
            Map<String, Object> imgMap = new HashMap<>();
            imgMap.put("image", "file://" + safePath);
            Map<String, Object> txtMap = new HashMap<>();
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
                .content(Arrays.asList(imgMap, txtMap))
                .build();
                
            com.alibaba.dashscope.aigc.multimodalconversation.MultiModalConversationParam param = com.alibaba.dashscope.aigc.multimodalconversation.MultiModalConversationParam.builder()
                .apiKey(apiKey)
                .model("qwen-vl-plus")
                .message(userMessage)
                .build();
                
            Method callMethod = conv.getClass().getMethod("call", com.alibaba.dashscope.aigc.multimodalconversation.MultiModalConversationParam.class);
            Object result = callMethod.invoke(conv, param);
            
            Method getOutputMethod = result.getClass().getMethod("getOutput");
            Object output = getOutputMethod.invoke(result);
            
            Method getChoicesMethod = output.getClass().getMethod("getChoices");
            List<?> choices = (List<?>) getChoicesMethod.invoke(output);
            
            Object choice = choices.get(0);
            Method getMessageMethod = choice.getClass().getMethod("getMessage");
            Object message = getMessageMethod.invoke(choice);
            
            Method getContentMethod = message.getClass().getMethod("getContent");
            List<?> contentList = (List<?>) getContentMethod.invoke(message);
            
            Map<?, ?> contentMap = (Map<?, ?>) contentList.get(0);
            String jsonResult = (String) contentMap.get("text");
            if (jsonResult != null) {
                jsonResult = jsonResult.replaceAll("^```(?:json)?\\s*", "").replaceAll("\\s*```$", "").trim();
            }
            logger.info("审图清理结果: " + jsonResult);
            return jsonResult;
        } catch (Exception e) {
            logger.error("审图异常: " + absoluteImagePath, e);
            return "{\"action\":\"KEEP\"}";
        }
    }

    /**
     * 调用 AI 优化词根解析
     * @param spell 单词
     * @param originalExplain 原始解析
     * @param cigenDescription 词根本身的含义（来自 cigen 表）
     * @return 优化后的解析
     */
    public String optimizeCigenExplain(String spell, String originalExplain, String cigenDescription) {
        String systemPrompt = "你是一位专业的英语词源学家。请根据提供的词根含义，优化给定单词的词根解析。要求如下：\n" +
                "1. 必须清晰拆解前缀、词根、后缀（使用 + 连接）。\n" +
                "2. 必须包含且优先参考提供的【主词库词根含义】。\n" +
                "3. 使用“→”符号展示从字面义到最终引申义的演变逻辑。\n" +
                "4. 保持格式为：单词 [词性] 释义（拆解部分→...→最终义）。\n" +
                "5. 严格只返回优化后的解析文本，不要包含任何前导说明文字。\n" +
                "\n" +
                "示例：\n" +
                "词根含义：[sym- 共同]\n" +
                "输入单词及原解析：[symmetry n 对称（sym共同+metry测量）]\n" +
                "返回：symmetry n 对称（sym共同+metry测量→两边测量一样→对称）";

        String userPrompt = "主词库词根含义：[" + cigenDescription + "]\n" +
                "目标单词：[" + spell + "]\n" +
                "原始解析：[" + originalExplain + "]";
        try {
            return generateText(systemPrompt, userPrompt);
        } catch (Exception e) {
            logger.error("AI 优化词根解析常: " + spell, e);
            return originalExplain;
        }
    }

    /**
     * 将杂乱的词根描述字符串解析为结构化 JSON
     * @param description 原始描述 (如: anti-表示\"反对，相反\")
     * @return JSON 格式: {"spell": "anti", "category": "PREFIX", "meaningCn": "反对，相反", "meaningEn": "against, opposite"}
     */
    public String parseCigenDescription(String description) {
        String systemPrompt = "你是一位精通词源学的专家。请将用户提供的非结构化英文词根描述解析为结构化数据。\n" +
                "规则：\n" +
                "1. spell: 提取核心词根/前缀文本（移除连接符 - 或 =）。\n" +
                "2. category: 判定类型，必须返回 PREFIX (前缀), SUFFIX (后缀), 或 ROOT (词根)。带有 - 在后的通常是 PREFIX，在前的通常是 SUFFIX，不带符号或带 = 的通常是 ROOT。\n" +
                "3. meaningCn: 提取中文含义，去除多余的标点符号和说明。\n" +
                "4. meaningEn: 根据上下文提供最准确的英文对应词。\n" +
                "必须返回纯 JSON 对象，不要包含 Markdown 格式标签。\n" +
                "示例：\n" +
                "输入：anti-表示\"反对，相反\"\n" +
                "返回：{\"spell\": \"anti\", \"category\": \"PREFIX\", \"meaningCn\": \"反对，相反\", \"meaningEn\": \"against, opposite\"}";

        try {
            String result = generateText(systemPrompt, "待解析描述：[" + description + "]");
            if (result != null) {
                return result.replaceAll("^```(?:json)?\\s*", "").replaceAll("\\s*```$", "").trim();
            }
            return null;
        } catch (Exception e) {
            logger.error("AI 解析词根描述异常: " + description, e);
            return null;
        }
    }

    /**
     * 根据单词列表生成小短文
     * @param words 单词列表 (拼写)
     * @return 生成结果 (含短文或错误信息)
     */
    public Result<String> generateShortStory(List<String> words) {
        if (words == null || words.isEmpty()) {
            return Result.fail("没有单词可以生成短文。");
        }

        // 限制并发量，防止瞬间大量请求冲垮服务器
        int limit = sysParamUtil.getAiStoryConcurrencyLimit();
        if (activeAiStoryRequests.get() >= limit) {
            return Result.fail("服务器繁忙，AI 生成并发达到上限，请稍后再试");
        }

        activeAiStoryRequests.incrementAndGet();
        try {
            String systemPrompt = "你是一位出色的创意作家和英语老师。请使用用户提供的英文单词列表，创作一篇短小精悍且富有逻辑的小故事（约 100-200 词）。\n" +
                    "要求：\n" +
                    "1. 必须使用列表中所有的单词（忽略大小写差异）。\n" +
                    "2. 故事内容应当生动有趣，且易于理解。\n" +
                    "3. 单词应当自然融入背景，加粗显示（如：**apple**）。\n" +
                    "4. 同时提供对应的中文翻译，放在英文文章之后。";

            String userPrompt = "单词列表：" + String.join(", ", words);
            String story = generateText(systemPrompt, userPrompt);
            return Result.success(story);
        } catch (Exception e) {
            return Result.fail(e.getMessage());
        } finally {
            activeAiStoryRequests.decrementAndGet();
        }
    }
    /**
     * 调用阿里云文档解析 API 将 PDF 转换为单词列表
     * @param pdfFile PDF 文件对象
     * @return 单词列表文本 (每行一个)
     */
    public String parsePdfToWords(File pdfFile) {
        String apiKey = aiProperties.getApiKey();
        if (apiKey == null || apiKey.isEmpty() || apiKey.startsWith("${")) {
            throw new RuntimeException("AI 调用失败: API Key 未设置");
        }

        try {
            logger.info("开始请求阿里云文档解析 (HTTP API): {}", pdfFile.getName());
            // 使用 OkHttp3 以支持更广泛的 SSL/TLS 协议，解决 No appropriate protocol 异常
            RestTemplate restTemplate = new RestTemplate(new OkHttp3ClientHttpRequestFactory());

            // 1. 上传文件到 DashScope
            String uploadUrl = "https://dashscope.aliyuncs.com/api/v1/files";
            HttpHeaders uploadHeaders = new HttpHeaders();
            uploadHeaders.set("Authorization", "Bearer " + apiKey);
            uploadHeaders.setContentType(MediaType.MULTIPART_FORM_DATA);

            MultiValueMap<String, Object> uploadBody = new LinkedMultiValueMap<>();
            uploadBody.add("file", new FileSystemResource(pdfFile));
            uploadBody.add("purpose", "file-extract");

            HttpEntity<MultiValueMap<String, Object>> uploadRequest = new HttpEntity<>(uploadBody, uploadHeaders);
            ResponseEntity<Map<String, Object>> uploadResponse = restTemplate.exchange(uploadUrl, HttpMethod.POST, uploadRequest, new org.springframework.core.ParameterizedTypeReference<Map<String, Object>>() {});

            if (!uploadResponse.getStatusCode().is2xxSuccessful() || uploadResponse.getBody() == null) {
                throw new RuntimeException("文件上传失败: " + uploadResponse.getStatusCode());
            }

            Map<String, Object> uploadBodyMap = uploadResponse.getBody();
            String fileId = null;
            try {
                if (uploadBodyMap.get("data") instanceof Map) {
                    @SuppressWarnings("unchecked")
                    Map<String, Object> data = (Map<String, Object>) uploadBodyMap.get("data");
                    List<?> uploadedFiles = (List<?>) data.get("uploaded_files");
                    if (uploadedFiles != null && !uploadedFiles.isEmpty()) {
                        fileId = (String) ((Map<?, ?>) uploadedFiles.get(0)).get("file_id");
                    }
                }
                if (fileId == null) {
                    fileId = (String) uploadBodyMap.get("id");
                }
            } catch (Exception e) {
                logger.warn("解析文件上传响应异常: {}", e.getMessage());
            }

            if (fileId == null) {
                throw new RuntimeException("文件上传成功但无法获取 fileId, 响应内容: " + uploadBodyMap);
            }
            logger.info("文件上传成功, fileId: {}", fileId);

            // 2. 提交解析任务 (使用 OpenAI 兼容接口以获得更好的 file_id 支持)
            String submitUrl = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions";
            HttpHeaders headers = new HttpHeaders();
            headers.set("Authorization", "Bearer " + apiKey);
            headers.setContentType(MediaType.APPLICATION_JSON);

            // 构建 Qwen-Doc-Turbo 的多模态输入格式
            Map<String, Object> body = new HashMap<>();
            List<Map<String, Object>> messages = new ArrayList<>();
            Map<String, Object> userMessage = new HashMap<>();
            userMessage.put("role", "user");

            List<Map<String, Object>> contentArr = new ArrayList<>();
            Map<String, Object> textPart = new HashMap<>();
            textPart.put("type", "text");
            textPart.put("text", "请解析该文档，将其中的所有表格以 Markdown 格式完整输出，不要遗漏任何单词。");
            contentArr.add(textPart);

            Map<String, Object> docPart = new HashMap<>();
            docPart.put("type", "file_id");
            docPart.put("file_id", fileId);
            contentArr.add(docPart);

            userMessage.put("content", contentArr);
            messages.add(userMessage);
            
            body.put("messages", messages);
            body.put("model", "qwen-doc-turbo");

            HttpEntity<Map<String, Object>> requestEntity = new HttpEntity<>(body, headers);
            ResponseEntity<Map<String, Object>> response = restTemplate.exchange(submitUrl, HttpMethod.POST, requestEntity, new org.springframework.core.ParameterizedTypeReference<Map<String, Object>>() {});

            Map<String, Object> responseBody = response.getBody();
            if (!response.getStatusCode().is2xxSuccessful() || responseBody == null) {
                throw new RuntimeException("提交解析任务失败: " + response.getStatusCode() + ", 响应: " + responseBody);
            }

            String markdown = null;
            // 1. 尝试从顶层 choices 获取 (OpenAI 兼容格式)
            if (responseBody.get("choices") instanceof List) {
                List<?> choices = (List<?>) responseBody.get("choices");
                if (!choices.isEmpty() && choices.get(0) instanceof Map) {
                    Map<?, ?> choice = (Map<?, ?>) choices.get(0);
                    if (choice.get("message") instanceof Map) {
                        markdown = (String) ((Map<?, ?>) choice.get("message")).get("content");
                    }
                }
            }
            
            // 2. 尝试从 output.choices 或 output.results 获取 (DashScope 原生格式)
            if (markdown == null && responseBody.get("output") instanceof Map) {
                Map<?, ?> output = (Map<?, ?>) responseBody.get("output");
                if (output.get("choices") instanceof List) {
                    List<?> choices = (List<?>) output.get("choices");
                    if (!choices.isEmpty() && choices.get(0) instanceof Map) {
                        Map<?, ?> choice = (Map<?, ?>) choices.get(0);
                        if (choice.get("message") instanceof Map) {
                            markdown = (String) ((Map<?, ?>) choice.get("message")).get("content");
                        }
                    }
                }
                if (markdown == null && output.get("results") instanceof List) {
                    List<?> results = (List<?>) output.get("results");
                    if (!results.isEmpty() && results.get(0) instanceof Map) {
                        markdown = (String) ((Map<?, ?>) results.get(0)).get("content");
                    }
                }
            }

            if (markdown == null || markdown.isEmpty()) {
                throw new RuntimeException("文档解析未返回内容, 响应内容: " + responseBody);
            }

            // 解析 Markdown 表格，提取第二列单词
            return extractWordsFromMarkdown(markdown);
        } catch (Exception e) {
            logger.error("阿里云文档解析异常", e);
            throw new RuntimeException("文档解析失败: " + e.getMessage());
        }
    }

    /**
     * 从 Markdown 中提取表格的第二列单词
     */
    private String extractWordsFromMarkdown(String markdown) {
        StringBuilder sb = new StringBuilder();
        Set<String> words = new LinkedHashSet<>();
        
        // 匹配 Markdown 表格行的正则: | col1 | col2 | col3 |
        // 允许单元格内有空格或特殊字符
        Pattern rowPattern = Pattern.compile("\\|([^|]*)\\|([^|]+)\\|([^|]*)");
        
        String[] lines = markdown.split("\n");
        for (String line : lines) {
            Matcher m = rowPattern.matcher(line);
            if (m.find()) {
                String word = m.group(2).trim();
                // 排除表头和分隔符行
                if (word.equalsIgnoreCase("Word") || word.matches("-+")) {
                    continue;
                }
                if (!word.isEmpty()) {
                    words.add(word);
                }
            }
        }
        
        for (String w : words) {
            sb.append(w).append("\n");
        }
        return sb.toString();
    }
}
