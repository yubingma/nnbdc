package beidanci.service.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import com.fasterxml.jackson.databind.ObjectMapper;
import beidanci.api.Result;
import beidanci.service.bo.AiBo;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.po.SysParam;
import beidanci.service.po.User;
import beidanci.service.util.SysParamUtil;
import javax.servlet.http.HttpServletRequest;
import java.util.*;
import java.util.concurrent.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import org.springframework.http.MediaType;
import com.alibaba.dashscope.common.Message;
import com.alibaba.dashscope.aigc.generation.GenerationResult;
import io.reactivex.Flowable;
import org.slf4j.MDC;

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

    private static final ObjectMapper mapper = new ObjectMapper();

    private final  ExecutorService aiChatExecutor =  Executors.newFixedThreadPool(50);

    /**
     * 根据单词列表生成小短文
     * @param wordsJson JSON array of word spells
     * @return 生成的小短文
     */
    @PostMapping("/ai/generateAiShortStory.do")
    public Result<String> generateAiShortStory(
            @RequestParam("wordsJson") String wordsJson,
            @RequestParam("userId") String userId) {
        try {
            // 验证用户身份
            if (userBo.findById(userId) == null) {
                return Result.fail("用户身份验证失败");
            }

            List<String> words = mapper.readValue(wordsJson, mapper.getTypeFactory().constructCollectionType(List.class, String.class));
            return aiBo.generateShortStory(words);
        } catch (Exception e) {
            return Result.fail(e.getMessage());
        }
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

                Flowable<GenerationResult> resultFlowable = aiBo.chatStream(messages);
                resultFlowable.blockingSubscribe(
                    result -> {
                        String content = result.getOutput().getChoices().get(0).getMessage().getContent();
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
                    },
                    () -> {
                        emitter.complete();
                    }
                );
            } catch (Exception e) {
                log.error("AI 聊天处理发生异常", e);
                try {
                    Result<String> failRs = Result.fail(e.getMessage());
                    emitter.send(Objects.requireNonNull(failRs));
                    emitter.complete();
                } catch (Exception ignore) {}
            } finally {
                if (admissionResult != null && admissionResult.isSuccess() && admissionResult.getData() != null) {
                    admissionResult.getData().run();
                }
                MDC.clear();
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
        try {
            if (userBo.findById(userId) == null) {
                return Result.fail("用户身份验证失败");
            }

             List<Message> messages = new  ArrayList<>();
            com.fasterxml.jackson.databind.JsonNode arrayNode = mapper.readTree(messagesJson);
            for (com.fasterxml.jackson.databind.JsonNode node : arrayNode) {
                messages.add(Message.builder()
                        .role(node.get("role").asText())
                        .content(node.get("content").asText())
                        .build());
            }
            String result = aiBo.chat(messages);
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail(e.getMessage());
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
}
