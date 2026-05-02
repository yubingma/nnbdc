package beidanci.service.bo;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashMap;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;

import javax.imageio.ImageIO;

import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.rendering.PDFRenderer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.OkHttp3ClientHttpRequestFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import com.alibaba.dashscope.aigc.generation.Generation;
import com.alibaba.dashscope.aigc.generation.GenerationParam;
import com.alibaba.dashscope.aigc.generation.GenerationResult;
import com.alibaba.dashscope.aigc.imagesynthesis.ImageSynthesis;
import com.alibaba.dashscope.aigc.imagesynthesis.ImageSynthesisParam;
import com.alibaba.dashscope.aigc.imagesynthesis.ImageSynthesisResult;
import com.alibaba.dashscope.audio.tts.SpeechSynthesisParam;
import com.alibaba.dashscope.audio.tts.SpeechSynthesizer;
import com.alibaba.dashscope.common.Message;
import com.alibaba.dashscope.common.Role;
import com.alibaba.dashscope.exception.InputRequiredException;
import com.alibaba.dashscope.exception.NoApiKeyException;

import beidanci.api.Result;
import beidanci.service.config.AliyunAiProperties;
import beidanci.service.po.AiStory;
import beidanci.service.util.SysParamUtil;
import io.reactivex.Flowable;

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

    @Autowired
    private AiStoryBo aiStoryBo;

    private final AtomicInteger activeAiStoryRequests = new AtomicInteger(0);
    private final AtomicInteger activeAiChatRequests = new AtomicInteger(0);
    private final ConcurrentHashMap<String, AtomicInteger> userAiChatRequests = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, AtomicInteger> userDailyAiChatRequests = new ConcurrentHashMap<>();
    private final Map<String, java.util.concurrent.CompletableFuture<Result<String>>> inFlightStories = new ConcurrentHashMap<>();

    public static class ExtractionTask {
        public final String taskId;
        public final String fileName;
        public final long fileSize;
        public final long startTime = System.currentTimeMillis();
        public final List<String> pageResults = new java.util.concurrent.CopyOnWriteArrayList<>();
        public final Map<Integer, String> failedPages = new java.util.concurrent.ConcurrentHashMap<>(); // 记录失败的页码及其错误
        public final java.util.Set<java.util.function.BiConsumer<Integer, String>> listeners = ConcurrentHashMap.newKeySet();
        public final java.util.Set<Consumer<String>> errorListeners = ConcurrentHashMap.newKeySet();
        public final java.util.Set<Consumer<String>> warningListeners = ConcurrentHashMap.newKeySet();
        public final java.util.Set<java.util.function.BiConsumer<Integer, String>> pageErrorListeners = ConcurrentHashMap.newKeySet();
        public final java.util.Set<Runnable> completionListeners = ConcurrentHashMap.newKeySet();
        public volatile int totalPages = 0;
        public volatile int processedPages = 0;
        public volatile boolean isFinished = false;
        public volatile boolean isStarted = false;
        public volatile boolean isStopped = false;
        public volatile String error = null;
        public File pdfFile;
        public long lastAccessTime = System.currentTimeMillis();

        public ExtractionTask(String taskId, String fileName, long fileSize, File pdfFile) {
            this.taskId = taskId;
            this.fileName = fileName;
            this.fileSize = fileSize;
            this.pdfFile = pdfFile;
        }

        public void addPageWords(int pageIndex, String words) {
            pageResults.add(words);
            lastAccessTime = System.currentTimeMillis();
            for (java.util.function.BiConsumer<Integer, String> listener : listeners) {
                try {
                    listener.accept(pageIndex, words);
                } catch (Exception ignore) {}
            }
        }

        public void finish() {
            isFinished = true;
            lastAccessTime = System.currentTimeMillis();
            for (Runnable listener : completionListeners) {
                try {
                    listener.run();
                } catch (Exception ignore) {}
            }
        }

        public void setError(String error) {
            this.error = error;
            lastAccessTime = System.currentTimeMillis();
            for (Consumer<String> listener : errorListeners) {
                try {
                    listener.accept(error);
                } catch (Exception ignore) {}
            }
        }

        public void notifyWarning(String warning) {
            this.error = warning; // 记录最近的一个警告信息
            lastAccessTime = System.currentTimeMillis();
            for (Consumer<String> listener : warningListeners) {
                try {
                    listener.accept(warning);
                } catch (Exception ignore) {}
            }
        }

        public void notifyPageError(int pageIndex, String errorMsg) {
            lastAccessTime = System.currentTimeMillis();
            for (java.util.function.BiConsumer<Integer, String> listener : pageErrorListeners) {
                try {
                    listener.accept(pageIndex, errorMsg);
                } catch (Exception ignore) {}
            }
        }
    }

    private final Map<String, ExtractionTask> extractionTaskStore = new ConcurrentHashMap<>();

    public ExtractionTask getOrCreateExtractionTask(String taskId, String fileName, long fileSize, File pdfFile) {
        return extractionTaskStore.computeIfAbsent(taskId, k -> new ExtractionTask(taskId, fileName, fileSize, pdfFile));
    }

    public ExtractionTask getExtractionTask(String taskId) {
        return extractionTaskStore.get(taskId);
    }

    public List<ExtractionTask> getAllExtractionTasks() {
        return new ArrayList<>(extractionTaskStore.values());
    }

    public boolean stopExtractionTask(String taskId) {
        ExtractionTask task = extractionTaskStore.get(taskId);
        if (task != null) {
            task.isStopped = true;
            task.setError("任务已被管理员停止");
            return true;
        }
        return false;
    }

    public boolean removeExtractionTask(String taskId) {
        ExtractionTask task = extractionTaskStore.remove(taskId);
        if (task != null) {
            task.isStopped = true;
            if (task.pdfFile != null && task.pdfFile.exists()) {
                task.pdfFile.delete();
            }
            return true;
        }
        return false;
    }

    public void resumeExtractionTask(String taskId, Integer startPage) {
        ExtractionTask task = extractionTaskStore.get(taskId);
        if (task != null && task.isStopped && !task.isFinished) {
            task.isStopped = false;
            task.error = null;
            if (startPage != null && startPage > 0) {
                task.processedPages = startPage - 1; // 转换为 0-based 索引
            }
            new Thread(() -> parsePdfToWordsTask(task.pdfFile, task)).start();
        }
    }

    @Scheduled(fixedRate = 3600000) // 每小时清理一次
    public void cleanupOldExtractionTasks() {
        long twelveHoursAgo = System.currentTimeMillis() - 12 * 3600 * 1000;
        int initialSize = extractionTaskStore.size();
        extractionTaskStore.entrySet().removeIf(entry -> {
            boolean isExpired = entry.getValue().lastAccessTime < twelveHoursAgo;
            if (isExpired && entry.getValue().pdfFile != null && entry.getValue().pdfFile.exists()) {
                entry.getValue().pdfFile.delete();
            }
            return isExpired;
        });
        if (extractionTaskStore.size() < initialSize) {
            logger.info("已清理过期的 PDF 解析任务，当前剩余任务数: {}", extractionTaskStore.size());
        }
    }

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

        // 1. 全局并发检查 (使用自旋保证原子性)
        while (true) {
            int current = activeAiChatRequests.get();
            if (current >= globalLimit) {
                logger.warn("AI 系统全局并发达到上限: {}, 拒绝来自用户 [{}]({}) 的请求", globalLimit, userId, userIdentifier);
                return Result.fail("服务器 AI 服务并发达到上限，请稍后再试");
            }
            if (activeAiChatRequests.compareAndSet(current, current + 1)) {
                break;
            }
        }

        // 2. 用户并发检查 (使用自旋保证原子性)
        AtomicInteger userCount = userAiChatRequests.computeIfAbsent(userId, k -> new AtomicInteger(0));
        while (true) {
            int current = userCount.get();
            if (current >= userLimit) {
                activeAiChatRequests.decrementAndGet(); // 回退全局计数
                logger.warn("单用户 AI 并发达到上限: 用户 [{}]({}) 已达 {} 并发", userId, userIdentifier, userLimit);
                return Result.fail("您的 AI 聊天并发请求过多，请等待上一个回复结束");
            }
            if (userCount.compareAndSet(current, current + 1)) {
                break;
            }
        }

        // 3. 今日次数检查
        AtomicInteger userDailyCount = userDailyAiChatRequests.computeIfAbsent(userId, k -> new AtomicInteger(0));
        while (true) {
            int current = userDailyCount.get();
            if (current >= userDailyLimit) {
                activeAiChatRequests.decrementAndGet(); // 回退全局计数
                userCount.decrementAndGet();           // 回退用户并发计数
                logger.warn("用户今日 AI 聊天次数达到上限: 用户 [{}]({}) 已达 {} 次", userId, userIdentifier, userDailyLimit);
                return Result.fail("您今日的 AI 聊天次数已达到上限 (" + userDailyLimit + "次)，请明天再试");
            }
            if (userDailyCount.compareAndSet(current, current + 1)) {
                break;
            }
        }

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
        String[] voices = {"longanyang", "longanhuan", "longxiaochun_v3", "longxiaoxia_v3"};
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
            return beidanci.service.util.JsonUtils.repairAiJson(result);
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

        // 1. 生成一致的 Key (去重、小写、排序后哈希)
        List<String> normalizedWords = new ArrayList<>();
        for (String w : words) {
            String lower = w.trim().toLowerCase();
            if (!normalizedWords.contains(lower)) {
                normalizedWords.add(lower);
            }
        }
        Collections.sort(normalizedWords);
        String wordsJsonForHash = beidanci.service.util.JsonUtils.toJson(normalizedWords);
        String wordsHash = org.apache.commons.codec.digest.DigestUtils.md5Hex(wordsJsonForHash);

        // 2. 检查缓存
        AiStory cachedStory = aiStoryBo.findByWordsHash(wordsHash);
        if (cachedStory != null) {
            logger.info("命中 AI 短文缓存: {}", wordsHash);
            return Result.success(cachedStory.getStoryContent());
        }

        // 3. 检查是否有正在生成的任务
        java.util.concurrent.CompletableFuture<Result<String>> future = inFlightStories.computeIfAbsent(wordsHash, k -> {
            return java.util.concurrent.CompletableFuture.supplyAsync(() -> {
                try {
                    return doGenerateShortStory(words, wordsHash, wordsJsonForHash);
                } finally {
                    inFlightStories.remove(k);
                }
            });
        });

        try {
            // 等待生成结果 (如果是预生成请求，这里也会阻塞，但它是异步发起的，所以没关系)
            return future.get(60, java.util.concurrent.TimeUnit.SECONDS);
        } catch (Exception e) {
            logger.error("获取 AI 短文失败", e);
            return Result.fail("生成 AI 短文超时或失败: " + e.getMessage());
        }
    }

    private Result<String> doGenerateShortStory(List<String> words, String wordsHash, String wordsJsonForHash) {
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
            String storyContent = generateText(systemPrompt, userPrompt);

            // 存入持久化缓存
            try {
                AiStory aiStory = new AiStory(java.util.UUID.randomUUID().toString().replace("-", ""), wordsHash, wordsJsonForHash, storyContent);
                aiStory.setCreateTime(new java.util.Date());
                aiStory.setUpdateTime(new java.util.Date());
                aiStoryBo.createEntity(aiStory);
            } catch (Exception e) {
                logger.error("保存 AI 短文缓存失败", e);
            }

            return Result.success(storyContent);
        } catch (Exception e) {
            logger.error("AI 生成短文失败", e);
            return Result.fail("AI 生成短文失败: " + e.getMessage());
        } finally {
            activeAiStoryRequests.decrementAndGet();
        }
    }
    /**
     * 调用阿里云AI OCR 将 PDF 转换为单词列表 (流式解析)
     * @param pdfFile PDF 文件对象
     * @param onPageExtracted 每解析出一页单词时的回调
     */
    public void parsePdfToWordsStream(File pdfFile, Consumer<String> onPageExtracted) {
        parsePdfToWordsStream(pdfFile, onPageExtracted, () -> false);
    }

    /**
     * 调用阿里云AI OCR 将 PDF 转换为单词列表 (流式解析，支持后台任务)
     * @param pdfFile PDF 文件对象
     * @param task 内存任务对象
     */
    public void parsePdfToWordsTask(File pdfFile, ExtractionTask task) {
        String apiKey = aiProperties.getApiKey();
        if (apiKey == null || apiKey.isEmpty() || apiKey.startsWith("${")) {
            task.setError("AI 调用失败: API Key 未设置");
            return;
        }

        try {
            // 1. PDF 转图片 (如果是恢复任务，且图片已生成过，理论上可以缓存，这里为了简单每次重新生成图片列表，开销较小)
            List<String> pageImagesBase64 = convertPdfToImagesBase64(pdfFile);
            task.totalPages = pageImagesBase64.size();
            logger.info("PDF 转换为 {} 张图片 (TaskID: {})", task.totalPages, task.taskId);
            
            // 2. 逐页 OCR 识别
            for (int i = task.processedPages; i < pageImagesBase64.size(); i++) {
                if (task.isStopped) {
                    logger.info("任务已停止，中断 OCR 处理 (TaskID: {})", task.taskId);
                    return;
                }
                
                long startTime = System.currentTimeMillis();
                logger.info("OCR 处理第 {}/{} 页 (TaskID: {})", i + 1, task.totalPages, task.taskId);
                try {
                    String pageResult = ocrImageWithQwenVL(pageImagesBase64.get(i));
                    if (pageResult != null && !pageResult.isEmpty()) {
                        String pageWords = extractWordsFromMarkdown(pageResult);
                        if (!pageWords.isEmpty()) {
                            logger.info("第 {} 页成功提取 {} 个单词 (TaskID: {})", i + 1, pageWords.split("\n").length, task.taskId);
                            task.addPageWords(i + 1, pageWords);
                        } else {
                            logger.warn("第 {} 页未提取到任何有效单词 (TaskID: {})", i + 1, task.taskId);
                        }
                    } else {
                        throw new RuntimeException("OCR 返回结果为空");
                    }
                } catch (Exception e) {
                    String errorMsg = "第 " + (i + 1) + " 页解析失败: " + e.getMessage();
                    logger.error(errorMsg + " (TaskID: " + task.taskId + ")", e);
                    task.failedPages.put(i + 1, e.getMessage()); // 记录失败页
                    task.notifyPageError(i + 1, e.getMessage()); // 立即通知监听器该页失败
                    task.setError(errorMsg);
                    task.isStopped = true;
                    return;
                }
                
                long duration = System.currentTimeMillis() - startTime;
                logger.info("第 {}/{} 页处理完成 (含可能的失败)，耗时 {} ms (TaskID: {})", i + 1, task.totalPages, duration, task.taskId);
                task.processedPages++;
            }
            logger.info("OCR 全部完成 (TaskID: {})", task.taskId);
            task.finish();
            // 只有全部完成后才删除文件
            if (pdfFile != null && pdfFile.exists()) {
                pdfFile.delete();
            }
        } catch (Exception e) {
            logger.error("阿里云文档解析异常 (TaskID: " + task.taskId + ")", e);
            task.setError("文档解析出现致命错误: " + e.getMessage());
            task.isStopped = true;
        }
    }

    /**
     * 兼容旧版本的流式解析方法
     */
    public void parsePdfToWordsStream(File pdfFile, Consumer<String> onPageExtracted,
                                      BooleanSupplier isDisconnected) {
        String taskId = "legacy_" + System.currentTimeMillis();
        ExtractionTask task = new ExtractionTask(taskId, pdfFile.getName(), pdfFile.length(), pdfFile);
        task.listeners.add((pageIndex, pageWords) -> onPageExtracted.accept(pageWords));
        parsePdfToWordsTask(pdfFile, task);
    }

    /**
     * 调用阿里云AI OCR 将 PDF 转换为单词列表
     * 流程: PDF -> 图片 -> Qwen-VL OCR -> Markdown -> 单词列表
     * @param pdfFile PDF 文件对象
     * @return 单词列表文本 (每行一个)
     */
    public String parsePdfToWords(File pdfFile) {
        String taskId = "sync_" + System.currentTimeMillis();
        ExtractionTask task = new ExtractionTask(taskId, pdfFile.getName(), pdfFile.length(), pdfFile);
        parsePdfToWordsTask(pdfFile, task);
        
        if (task.error != null) {
            throw new RuntimeException(task.error);
        }
        
        StringBuilder allWords = new StringBuilder();
        for (String pageWords : task.pageResults) {
            allWords.append(pageWords);
        }
        return allWords.toString();
    }
    
    /**
     * 将 PDF 每一页转换为 Base64 编码的图片
     */
    private List<String> convertPdfToImagesBase64(File pdfFile) throws IOException {
        List<String> images = new ArrayList<>();
        
        try (PDDocument document = PDDocument.load(pdfFile)) {
            PDFRenderer renderer = new PDFRenderer(document);
            int pageCount = document.getNumberOfPages();
            
            for (int i = 0; i < pageCount; i++) {
                BufferedImage image = renderer.renderImageWithDPI(i, 200);
                
                ByteArrayOutputStream baos = new ByteArrayOutputStream();
                ImageIO.write(image, "PNG", baos);
                byte[] imageBytes = baos.toByteArray();
                
                String base64 = Base64.getEncoder().encodeToString(imageBytes);
                images.add(base64);
                
                logger.debug("转换第 {}/{} 页", i + 1, pageCount);
            }
        }
        
        return images;
    }
    
    /**
     * 使用 Qwen-VL 对图片进行 OCR 识别
     */
    private String ocrImageWithQwenVL(String imageBase64) throws Exception {
        String apiKey = aiProperties.getApiKey();
        OkHttp3ClientHttpRequestFactory factory = new OkHttp3ClientHttpRequestFactory();
        factory.setConnectTimeout(120000);
        factory.setReadTimeout(120000);
        factory.setWriteTimeout(120000);
        RestTemplate restTemplate = new RestTemplate(factory);
        
        String url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions";
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + apiKey);
        headers.setContentType(MediaType.APPLICATION_JSON);
        
        Map<String, Object> body = new HashMap<>();
        body.put("model", "qwen-vl-max");
        
        List<Map<String, Object>> messages = new ArrayList<>();
        Map<String, Object> userMessage = new HashMap<>();
        userMessage.put("role", "user");
        
        List<Map<String, Object>> content = new ArrayList<>();
        
        Map<String, Object> imageBlock = new HashMap<>();
        imageBlock.put("type", "image_url");
        Map<String, Object> imageUrl = new HashMap<>();
        imageUrl.put("url", "data:image/png;base64," + imageBase64);
        imageBlock.put("image_url", imageUrl);
        content.add(imageBlock);
        
        Map<String, Object> textBlock = new HashMap<>();
        textBlock.put("type", "text");
        textBlock.put("text", "请识别图片中的所有单词及其对应的所有中文释义。请按Markdown表格格式输出（包含：序号、单词、释义）。务必识别并列出图片中的【每一个】单词，不要有任何遗漏。");
        content.add(textBlock);
        
        userMessage.put("content", content);
        messages.add(userMessage);
        
        body.put("messages", messages);
        
        HttpEntity<Map<String, Object>> requestEntity = new HttpEntity<>(body, headers);
        ResponseEntity<Map<String, Object>> response = restTemplate.exchange(url, HttpMethod.POST, requestEntity, 
            new org.springframework.core.ParameterizedTypeReference<Map<String, Object>>() {});
        
        Map<String, Object> responseBody = response.getBody();
        if (!response.getStatusCode().is2xxSuccessful() || responseBody == null) {
            logger.warn("OCR 调用失败: {}", responseBody);
            return null;
        }
        
        List<?> choices = (List<?>) responseBody.get("choices");
        if (choices == null || choices.isEmpty()) {
            return null;
        }
        
        Map<?, ?> choice = (Map<?, ?>) choices.get(0);
        if (choice == null || choice.get("message") == null) {
            return null;
        }
        
        Map<?, ?> message = (Map<?, ?>) choice.get("message");
        return (String) message.get("content");
    }

    /**
     * 从 Markdown 中提取表格的单词和释义
     * 返回格式：每行一个 "单词\t释义"
     */
    private String extractWordsFromMarkdown(String markdown) {
        StringBuilder sb = new StringBuilder();
        String[] lines = markdown.split("\\R");
        for (String line : lines) {
            line = line.trim();
            if (!line.contains("|")) continue;
            
            // 将行按 | 分割，并清理空白
            String[] rawParts = line.split("\\|");
            List<String> columns = new ArrayList<>();
            for (String part : rawParts) {
                String trimmed = part.trim();
                // 忽略首尾因 | 产生的空元素，但保留中间可能的空列
                columns.add(trimmed);
            }
            
            // 移除首尾空列（通常由首尾的 | 产生）
            if (!columns.isEmpty() && columns.get(0).isEmpty()) columns.remove(0);
            if (!columns.isEmpty() && columns.get(columns.size() - 1).isEmpty()) columns.remove(columns.size() - 1);

            if (columns.size() < 2) continue;

            // 提取关键内容
            String col1 = columns.get(0);
            String col2 = columns.get(1);
            
            // 排除表头和分隔符行
            if (col2.equalsIgnoreCase("Word") || col2.equalsIgnoreCase("单词") || 
                col2.contains("---") || col1.contains("---") || col1.equalsIgnoreCase("序号")) {
                continue;
            }
            
            String word = "";
            String meaning = "";
            
            // 根据列数启发式识别单词和释义
            if (columns.size() == 2) {
                word = col1;
                meaning = col2;
            } else if (columns.size() == 3) {
                // 可能是 | 序号 | 单词 | 释义 |
                if (col1.matches("\\d+")) {
                    word = col2;
                    meaning = columns.get(2);
                } else {
                    // 可能是 | 单词 | 属性 | 释义 |
                    word = col1;
                    meaning = columns.get(2);
                }
            } else {
                // 更多列的情况，通常单词在较前位置，释义在较后位置
                if (col1.matches("\\d+")) {
                    word = col2;
                } else {
                    word = col1;
                }
                meaning = columns.get(columns.size() - 1);
            }
            
            if (!word.isEmpty() && !word.contains("--")) {
                sb.append(word).append("\t").append(meaning).append("\n");
            }
        }
        return sb.toString();
    }
}
