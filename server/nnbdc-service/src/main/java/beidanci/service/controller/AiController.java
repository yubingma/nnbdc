package beidanci.service.controller;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import org.springframework.web.context.request.async.DeferredResult;
import java.util.concurrent.CompletableFuture;

import com.alibaba.dashscope.common.Message;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;

import beidanci.api.Result;
import beidanci.api.model.AiStoryVo;
import beidanci.service.bo.AiBo;
import beidanci.service.bo.EmbeddingBo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.SysParam;
import beidanci.service.util.SysParamUtil;
import io.reactivex.Flowable;

@RestController
public class AiController {
    private static final Logger log = LoggerFactory.getLogger(AiController.class);

    @Autowired
    private UserBo userBo;

    @Autowired
    private AiBo aiBo;

    @Autowired
    private SysParamUtil sysParamUtil;

    @Autowired
    private SysParamBo sysParamBo;

    @Autowired
    private EmbeddingBo embeddingBo;

    private static final ObjectMapper mapper = new ObjectMapper();

    private final  ExecutorService aiChatExecutor =  Executors.newFixedThreadPool(50);

    /**
     * 根据单词列表生成小短文
     * @param wordsJson JSON array of word spells
     * @return 生成的小短文
     */
    /**
     * 根据单词列表生成小短文（保留两个参数的重载，完美兼容 Java 内部的直接方法调用）
     */
    public DeferredResult<Result<AiStoryVo>> generateAiShortStory(
            String wordsJson,
            String userId) {
        return generateAiShortStory(wordsJson, userId, false);
    }

    @PostMapping("/ai/generateAiShortStory.do")
    public DeferredResult<Result<AiStoryVo>> generateAiShortStory(
            @RequestParam("wordsJson") String wordsJson,
            @RequestParam("userId") String userId,
            @RequestParam(value = "lazyAudio", required = false, defaultValue = "false") boolean lazyAudio) {
        DeferredResult<Result<AiStoryVo>> deferredResult = new DeferredResult<>(60000L); // 60秒超时
        deferredResult.onTimeout(() -> deferredResult.setErrorResult(Result.fail("生成 AI 短文超时")));

        try {
            // 验证用户身份
            if (userBo.findById(userId) == null) {
                deferredResult.setResult(Result.fail("用户身份验证失败"));
                return deferredResult;
            }

            List<String> words = mapper.readValue(wordsJson, mapper.getTypeFactory().constructCollectionType(List.class, String.class));
            CompletableFuture<Result<AiStoryVo>> future = aiBo.generateShortStory(words, userId, lazyAudio);
            
            future.thenAccept(result -> deferredResult.setResult(result))
                  .exceptionally(ex -> {
                      deferredResult.setErrorResult(Result.fail("生成异常: " + ex.getMessage()));
                      return null;
                  });
            
        } catch (Exception e) {
            deferredResult.setResult(Result.fail(e.getMessage()));
        }
        
        return deferredResult;
    }

    /**
     * 阿里云AI对话 (流式输出)
     */
    @PostMapping(value = "/ai/chatStream.do", produces = MediaType.TEXT_EVENT_STREAM_VALUE + ";charset=UTF-8")
    public SseEmitter aiChatStream(
            @RequestParam("messagesJson") String messagesJson,
            @RequestParam("userId") String userId) {
        SseEmitter emitter = new SseEmitter(300000L);
        
        // 验证用户身份 (ID 检查)
        if (userBo.findById(userId) == null) {
            try {
                emitter.send(Objects.requireNonNull(Result.fail("用户身份验证失败，请重新登录")));
                emitter.complete();
            } catch (Exception ignore) {}
            return emitter;
        }

        final Map<String, String> mdcContext = MDC.getCopyOfContextMap();
        final String finalUserIdentifier = MDC.get("userContext");
        final String finalClientType = MDC.get("platform");

        aiChatExecutor.execute(() -> {
            if (mdcContext != null) MDC.setContextMap(mdcContext);
            Result<Runnable> admissionResult = null;
            try {
                // 并发与流控逻辑
                admissionResult = aiBo.enterAiChat(userId, finalUserIdentifier, finalClientType);
                if (!admissionResult.isSuccess()) {
                    Result<String> failRs = Result.fail(admissionResult.getMsg());
                    emitter.send(Objects.requireNonNull(failRs));
                    emitter.complete();
                    return;
                }

                 List<Message> messages = new  ArrayList<>();
                com.fasterxml.jackson.databind.JsonNode arrayNode = mapper.readTree(messagesJson);
                for (com.fasterxml.jackson.databind.JsonNode node : arrayNode) {
                    messages.add(Message.builder()
                            .role(node.get("role").asText())
                            .content(node.get("content").asText())
                            .build());
                }

                Flowable<String> resultFlowable = aiBo.chatStream(messages);
                final Result<Runnable> finalAdmission = admissionResult;
                resultFlowable.subscribe(
                    content -> {
                        if (content != null) {
                            Result<String> rs = Result.success(content);
                            emitter.send(Objects.requireNonNull(rs));
                        }
                    },
                    error -> {
                        log.error("AI 聊天流发生错误", error);
                        Result<String> failRs = Result.fail(error.getMessage());
                        try { emitter.send(Objects.requireNonNull(failRs)); } catch (Exception ignore) {}
                        emitter.complete();
                        if (finalAdmission != null && finalAdmission.isSuccess() && finalAdmission.getData() != null) {
                            finalAdmission.getData().run();
                        }
                        MDC.clear();
                    },
                    () -> {
                        emitter.complete();
                        if (finalAdmission != null && finalAdmission.isSuccess() && finalAdmission.getData() != null) {
                            finalAdmission.getData().run();
                        }
                        MDC.clear();
                    }
                );
            } catch (Exception e) {
                log.error("AI 聊天处理发生异常", e);
                try {
                    Result<String> failRs = Result.fail(e.getMessage());
                    emitter.send(Objects.requireNonNull(failRs));
                    emitter.complete();
                } catch (Exception ignore) {}
                if (admissionResult != null && admissionResult.isSuccess() && admissionResult.getData() != null) {
                    admissionResult.getData().run();
                }
            } finally {
                // MDC 已在 onComplete/onError 中清理
            }
        });
        return emitter;
    }

    /**
     * 阿里云AI对话 (阻塞输出)
     */
    @PostMapping("/ai/chat.do")
    public Result<String> aiChat(
            @RequestParam("messagesJson") String messagesJson,
            @RequestParam("userId") String userId) {
        if (userBo.findById(userId) == null) {
            return Result.fail("用户身份验证失败");
        }

        final String userIdentifier = MDC.get("userContext") != null ? MDC.get("userContext") : "User(" + userId + ")";
        final String clientType = MDC.get("platform") != null ? MDC.get("platform") : "Unknown";

        Result<Runnable> admissionResult = aiBo.enterAiChat(userId, userIdentifier, clientType);
        if (!admissionResult.isSuccess()) {
            return Result.fail(admissionResult.getMsg());
        }

        try {
            List<Message> messages = new ArrayList<>();
            JsonNode arrayNode = mapper.readTree(messagesJson);
            for (JsonNode node : arrayNode) {
                messages.add(Message.builder()
                        .role(node.get("role").asText())
                        .content(node.get("content").asText())
                        .build());
            }
            String result = aiBo.chat(messages);
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail(e.getMessage());
        } finally {
            if (admissionResult.getData() != null) {
                admissionResult.getData().run();
            }
        }
    }

    /**
     * 获取 AI 相关配置
     */
    @GetMapping("/ai/getConfig.do")
    public Result<Map<String, Object>> getAiConfig() {
        Map<String, Object> config = new HashMap<>();
        
        config.put("concurrencyLimit", aiBo.getStoryConcurrencyLimit());
        config.put("aiChatGlobalLimit", sysParamUtil.getAiChatGlobalLimit());
        config.put("aiChatUserLimit", sysParamUtil.getAiChatUserLimit());
        config.put("aiChatUserDailyLimit", sysParamUtil.getAiChatUserDailyLimit());

        return Result.success(config);
    }

    /**
     * 保存 AI 相关配置
     */
    @PostMapping("/ai/saveConfig.do")
    public Result<String> saveAiConfig(
            @RequestParam("concurrencyLimit") int concurrencyLimit,
            @RequestParam(value = "aiChatGlobalLimit", defaultValue = "20") int aiChatGlobalLimit,
            @RequestParam(value = "aiChatUserLimit", defaultValue = "2") int aiChatUserLimit,
            @RequestParam(value = "aiChatUserDailyLimit", defaultValue = "100") int aiChatUserDailyLimit) throws IllegalAccessException {
        
        saveParam("AiStoryConcurrencyLimit", String.valueOf(concurrencyLimit), "AI 短文生成并发上限");
        saveParam("AiChatGlobalLimit", String.valueOf(aiChatGlobalLimit), "AI 聊天全局并发上限");
        saveParam("AiChatUserLimit", String.valueOf(aiChatUserLimit), "AI 聊天单用户并发上限");
        saveParam("AiChatUserDailyLimit", String.valueOf(aiChatUserDailyLimit), "AI 聊天单用户每日次数上限");

        return Result.success("系统配置保存成功");
    }

    private void saveParam(String name, String value, String comment) throws IllegalAccessException {
        SysParam param = sysParamBo.findById(name);
        if (param == null) {
            param = new SysParam(name, value, comment);
            sysParamBo.createEntity(param);
        } else {
            param.setParamValue(value);
            sysParamBo.updateEntity(param);
        }
    }

    /**
     * 按需生成并获取短文配音文件路径
     * @param wordsHash 短文散列值
     * @param lang 语种 ("en" 或 "cn")
     * @param userId 用户 ID
     * @return 配音文件的 URL 路径
     */
    @PostMapping("/ai/getOrGenerateStoryAudio.do")
    public Result<String> getOrGenerateStoryAudio(
            @RequestParam("wordsHash") String wordsHash,
            @RequestParam("lang") String lang,
            @RequestParam("userId") String userId) {
        try {
            // 验证用户身份
            if (userBo.findById(userId) == null) {
                return Result.fail("用户身份验证失败");
            }

            if (wordsHash == null || wordsHash.isEmpty() || lang == null || lang.isEmpty()) {
                return Result.fail("参数不完整");
            }

            String relativePath = aiBo.getOrGenerateAudioOnDemand(wordsHash, lang, userId);
            // 返回相对静态路径，以便前端直接播放，比如 /sound/ai_story/xxx_en.mp3
            return Result.success("/sound/" + relativePath);
        } catch (Exception e) {
            log.error("按需生成配音失败, hash=" + wordsHash + ", lang=" + lang, e);
            return Result.fail("生成配音失败: " + e.getMessage());
        }
    }

    /**
     * 获取词嵌入重构状态及度量
     */
    @GetMapping("/ai/embedding/status.do")
    public Result<Map<String, Object>> getEmbeddingStatus() {
        Map<String, Object> statusMap = new HashMap<>();
        statusMap.put("reconstructStatus", embeddingBo.getReconstructStatus());
        statusMap.put("reconstructMsg", embeddingBo.getReconstructMsg());
        statusMap.put("reconstructProgress", embeddingBo.getReconstructProgress());
        
        int total = embeddingBo.getTotalWordCount();
        int fitted = embeddingBo.getFittedWordCount();
        statusMap.put("totalWords", total);
        statusMap.put("fittedWords", fitted);
        
        double unreconstructedPercent = 0.0;
        if (total > 0) {
            unreconstructedPercent = (double) (total - fitted) / total;
        }
        statusMap.put("unreconstructedPercent", unreconstructedPercent);
        statusMap.put("warning", unreconstructedPercent >= 0.30);
        
        return Result.success(statusMap);
    }

    /**
     * 触发异步一键重构 PCA 空间
     */
    @PostMapping("/ai/embedding/reconstruct.do")
    public Result<String> triggerReconstruct() {
        try {
            embeddingBo.reconstructProjectionSpaceAsync();
            return Result.success("重构任务已成功触发");
        } catch (Exception e) {
            return Result.fail(e.getMessage());
        }
    }
}
