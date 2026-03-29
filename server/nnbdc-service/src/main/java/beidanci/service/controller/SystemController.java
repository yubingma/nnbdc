package beidanci.service.controller;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.DictStatsVo;
import beidanci.api.model.SystemHealthCheckResult;
import beidanci.api.model.SystemHealthFixResult;
import beidanci.service.bo.DictBo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.bo.SystemHealthCheckBo;
import beidanci.service.po.SysParam;
import beidanci.service.util.AliyunResourceUtil;
import beidanci.service.util.AliyunResourceUtil.AccountBalanceInfo;
import beidanci.service.util.CdnUtil;

@RestController
public class SystemController {


    
    @Autowired
    private DictBo dictBo;
    
    @Autowired
    private SystemHealthCheckBo systemHealthCheckBo;
    
    @Autowired
    private CdnUtil cdnUtil;
    
    @Autowired
    private SysParamBo sysParamBo;
    
    @Autowired
    private AliyunResourceUtil aliyunResourceUtil;

    @Autowired
    private beidanci.service.bo.AiBo aiBo;

    /**
     * 获取系统词典列表及其统计信息
     * 返回所有系统词典和每个词典被用户选择的数量
     */
    @GetMapping("/getSystemDictsWithStats.do")
    public Result<List<DictStatsVo>> getSystemDictsWithStats() {
        List<DictStatsVo> result = dictBo.getSystemDictsWithStats();
        return Result.success(result);
    }

    /**
     * 获取指定词典的详细统计信息
     */
    @GetMapping("/getDictStats.do")
    public Result<DictStatsVo> getDictStats(@RequestParam("dictId") String dictId) {
        DictStatsVo result = dictBo.getDictStats(dictId);
        return Result.success(result);
    }

    /**
     * 更新系统词典信息
     */
    @PostMapping("/updateSystemDict.do")
    public Result<String> updateSystemDict(
            @RequestParam("dictId") String dictId,
            @RequestParam("name") String name,
            @RequestParam("isReady") boolean isReady,
            @RequestParam("visible") boolean visible,
            @RequestParam(value = "popularityLimit", required = false) Integer popularityLimit
    ) {
        dictBo.updateSystemDict(dictId, name, isReady, visible, popularityLimit);
        return Result.success("词典信息更新成功");
    }

    /**
     * 更新词典中的单词信息
     */
    @PostMapping("/updateDictWord.do")
    public Result<String> updateDictWord(
            @RequestParam("wordId") String wordId,
            @RequestParam("spell") String spell,
            @RequestParam(value = "shortDesc", required = false) String shortDesc,
            @RequestParam(value = "longDesc", required = false) String longDesc,
            @RequestParam(value = "pronounce", required = false) String pronounce,
            @RequestParam(value = "americaPronounce", required = false) String americaPronounce,
            @RequestParam(value = "britishPronounce", required = false) String britishPronounce,
            @RequestParam(value = "popularity", required = false) Integer popularity
    ) {
        dictBo.updateDictWord(wordId, spell, shortDesc, longDesc, pronounce, 
                            americaPronounce, britishPronounce, popularity);
        return Result.success("单词信息更新成功");
    }

    /**
     * 从词典中删除单词
     */
    @PostMapping("/removeWordFromDict.do")
    public Result<String> removeWordFromDict(
            @RequestParam("dictId") String dictId,
            @RequestParam("wordId") String wordId
    ) {
        dictBo.removeWordFromDict(dictId, wordId);
        return Result.success("单词删除成功");
    }

    // ============================================
    // 系统健康检查相关API
    // ============================================

    /**
     * 检查系统词典完整性
     */
    @GetMapping("/admin/checkSystemDictIntegrity.do")
    public Result<SystemHealthCheckResult> checkSystemDictIntegrity() {
        SystemHealthCheckResult result = systemHealthCheckBo.checkSystemDictIntegrity();
        return Result.success(result);
    }

    /**
     * 检查系统词典是否缺失通用词库（0库）托底
     */
    @GetMapping("/admin/checkSysDictMissingFallback.do")
    public Result<SystemHealthCheckResult> checkSysDictMissingFallback() {
        SystemHealthCheckResult result = systemHealthCheckBo.checkSystemDictMissingFallback();
        return Result.success(result);
    }



    /**
     * 为客户端自愈拉取缺失单词包（非管理员接口）
     */
    @PostMapping("/api/getFallbackWordsData.do")
    public Result<java.util.Map<String, Object>> getFallbackWordsData(@RequestParam("wordIds") String wordIdsJson) {
        try {
            com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
            List<String> ids = mapper.readValue(wordIdsJson, new com.fasterxml.jackson.core.type.TypeReference<List<String>>(){});
            if (ids.isEmpty()) return Result.success(new java.util.HashMap<>());
            
            return Result.success(systemHealthCheckBo.getFallbackWordsData(ids));
        } catch (Exception e) {
            return Result.fail("获取基础补丁数据失败: " + e.getMessage());
        }
    }

    /**
     * 检查用户词典完整性
     */
    @GetMapping("/admin/checkUserDictIntegrity.do")
    public Result<SystemHealthCheckResult> checkUserDictIntegrity() {
        SystemHealthCheckResult result = systemHealthCheckBo.checkUserDictIntegrity();
        return Result.success(result);
    }

    

    /**
     * 检查数据库版本一致性
     */
    @GetMapping("/admin/checkDbVersionConsistency.do")
    public Result<SystemHealthCheckResult> checkDbVersionConsistency() {
        SystemHealthCheckResult result = systemHealthCheckBo.checkDbVersionConsistency();
        return Result.success(result);
    }

    /**
     * 检查通用词典完整性
     */
    @GetMapping("/admin/checkCommonDictIntegrity.do")
    public Result<SystemHealthCheckResult> checkCommonDictIntegrity() {
        SystemHealthCheckResult result = systemHealthCheckBo.checkCommonDictIntegrity();
        return Result.success(result);
    }

    /**
     * 检查所有用户的学习步骤完整性
     */
    @GetMapping("/admin/checkUserStudySteps.do")
    public Result<SystemHealthCheckResult> checkUserStudySteps() {
        SystemHealthCheckResult result = systemHealthCheckBo.checkUserStudySteps();
        return Result.success(result);
    }

    /**
     * 检查用户是否缺失生词本或已掌握词书
     */
    @GetMapping("/admin/checkMissingUserDicts.do")
    public Result<SystemHealthCheckResult> checkMissingUserDicts() {
        SystemHealthCheckResult result = systemHealthCheckBo.checkMissingUserDicts();
        return Result.success(result);
    }

    /**
     * 自动修复系统问题
     */
    @PostMapping("/admin/autoFixSystemIssues.do")
    public Result<SystemHealthFixResult> autoFixSystemIssues(
            @RequestParam("issueTypes") List<String> issueTypes
    ) {
        SystemHealthFixResult result = systemHealthCheckBo.autoFixSystemIssues(issueTypes);
        return Result.success(result);
    }

    /**
     * CDN缓存刷新
     * @param urls 需要刷新的URL列表，多个URL以换行符分隔
     * @param objectType 刷新类型：File（文件）或 Directory（目录）
     * @return 刷新结果
     */
    @PostMapping("/admin/refreshCdnCache.do")
    public Result<String> refreshCdnCache(
            @RequestParam("urls") String urls,
            @RequestParam(value = "objectType", defaultValue = "File") String objectType
    ) throws IllegalAccessException {
        String result = cdnUtil.refreshCache(urls, objectType);
        if ("OK".equals(result)) {
            return Result.success("缓存刷新任务提交成功");
        } else {
            return Result.fail(result);
        }
    }

    /**
     * 获取CDN刷新URL配置
     * @return 配置的URL列表（文件和目录）
     */
    @GetMapping("/admin/getCdnRefreshUrls.do")
    public Result<CdnUrlConfig> getCdnRefreshUrls() {
        String fileUrls = "";
        String dirUrls = "";
        
        SysParam fileParam = sysParamBo.findById("cdnRefreshFileUrls");
        if (fileParam != null) {
            fileUrls = fileParam.getParamValue();
        }
        
        SysParam dirParam = sysParamBo.findById("cdnRefreshDirUrls");
        if (dirParam != null) {
            dirUrls = dirParam.getParamValue();
        }
        
        CdnUrlConfig config = new CdnUrlConfig(fileUrls, dirUrls);
        return Result.success(config);
    }

    /**
     * 保存CDN刷新URL配置
     * @param fileUrls 文件URL列表，多个URL以换行符分隔
     * @param dirUrls 目录URL列表，多个URL以换行符分隔
     * @return 保存结果
     */
    @PostMapping("/admin/saveCdnRefreshUrls.do")
    public Result<String> saveCdnRefreshUrls(
            @RequestParam(value = "fileUrls", required = false, defaultValue = "") String fileUrls,
            @RequestParam(value = "dirUrls", required = false, defaultValue = "") String dirUrls
    ) throws IllegalAccessException {
        // 保存文件URL配置
        SysParam fileParam = sysParamBo.findById("cdnRefreshFileUrls");
        if (fileParam == null) {
            fileParam = new SysParam("cdnRefreshFileUrls", fileUrls, "CDN文件刷新URL配置");
            sysParamBo.createEntity(fileParam);
        } else {
            fileParam.setParamValue(fileUrls);
            sysParamBo.updateEntity(fileParam);
        }
        
        // 保存目录URL配置
        SysParam dirParam = sysParamBo.findById("cdnRefreshDirUrls");
        if (dirParam == null) {
            dirParam = new SysParam("cdnRefreshDirUrls", dirUrls, "CDN目录刷新URL配置");
            sysParamBo.createEntity(dirParam);
        } else {
            dirParam.setParamValue(dirUrls);
            sysParamBo.updateEntity(dirParam);
        }
        
        return Result.success("配置保存成功");
    }
    
    /**
     * CDN URL配置类
     */
    public static class CdnUrlConfig {
        private String fileUrls;
        private String dirUrls;
        
        public CdnUrlConfig(String fileUrls, String dirUrls) {
            this.fileUrls = fileUrls;
            this.dirUrls = dirUrls;
        }
        
        public String getFileUrls() {
            return fileUrls;
        }
        
        public void setFileUrls(String fileUrls) {
            this.fileUrls = fileUrls;
        }
        
        public String getDirUrls() {
            return dirUrls;
        }
        
        public void setDirUrls(String dirUrls) {
            this.dirUrls = dirUrls;
        }
    }

    /**
     * 查询阿里云账户余额
     * @return 账户余额信息
     */
    @GetMapping("/admin/queryAliyunBalance.do")
    public Result<AccountBalanceInfo> queryAliyunBalance() {
        AccountBalanceInfo balanceInfo = aliyunResourceUtil.queryAccountBalance();
        if ("查询成功".equals(balanceInfo.getMessage())) {
            return Result.success(balanceInfo);
        } else {
            return Result.fail(balanceInfo.getMessage());
        }
    }

    /**
     * 查询阿里云资源包使用情况
     * @return 资源包信息
     */
    @GetMapping("/admin/queryAliyunResourcePackages.do")
    public Result<String> queryAliyunResourcePackages() {
        String result = aliyunResourceUtil.queryResourcePackageInstances();
        // 如果是错误消息，返回失败；否则返回JSON数据
        if (result.startsWith("{") && result.contains("Instances")) {
            return Result.success(result);
        } else {
            return Result.fail(result);
        }
    }

    /**
     * 阿里云AI对话 (流式输出)
     * @param messagesJson JSON array of messages [{"role":"system","content":"..."}, ...]
     * @return 助手回复的流 (Server-Sent Events)
     */
    @PostMapping(value = "/admin/aiChatStream.do", produces = org.springframework.http.MediaType.TEXT_EVENT_STREAM_VALUE + ";charset=UTF-8")
    public org.springframework.web.servlet.mvc.method.annotation.SseEmitter aiChatStream(@RequestParam("messagesJson") String messagesJson) {
        org.springframework.web.servlet.mvc.method.annotation.SseEmitter emitter = new org.springframework.web.servlet.mvc.method.annotation.SseEmitter(300000L);
        java.util.concurrent.ExecutorService sseMvcExecutor = java.util.concurrent.Executors.newSingleThreadExecutor();
        sseMvcExecutor.execute(() -> {
            try {
                com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
                java.util.List<com.alibaba.dashscope.common.Message> messages = new java.util.ArrayList<>();
                com.fasterxml.jackson.databind.JsonNode arrayNode = mapper.readTree(messagesJson);
                for (com.fasterxml.jackson.databind.JsonNode node : arrayNode) {
                    messages.add(com.alibaba.dashscope.common.Message.builder()
                            .role(node.get("role").asText())
                            .content(node.get("content").asText())
                            .build());
                }

                io.reactivex.Flowable<com.alibaba.dashscope.aigc.generation.GenerationResult> resultFlowable = aiBo.chatStream(messages);
                resultFlowable.blockingSubscribe(
                    result -> {
                        String content = result.getOutput().getChoices().get(0).getMessage().getContent();
                        if (content != null) {
                            beidanci.api.Result<String> rs = beidanci.api.Result.success(content);
                            emitter.send(java.util.Objects.requireNonNull(rs));
                        }
                    },
                    error -> {
                        beidanci.api.Result<String> failRs = beidanci.api.Result.fail("AI服务异常: " + error.getMessage());
                        emitter.send(java.util.Objects.requireNonNull(failRs));
                        emitter.completeWithError(error);
                    },
                    () -> {
                        emitter.complete();
                    }
                );
            } catch (Exception e) {
                try {
                    beidanci.api.Result<String> failRs = beidanci.api.Result.fail("后端系统异常: " + e.getMessage());
                    emitter.send(java.util.Objects.requireNonNull(failRs));
                    emitter.completeWithError(e);
                } catch (Exception ignore) {}
            }
        });
        return emitter;
    }

    /**
     * 阿里云AI对话
     * @param messagesJson JSON array of messages [{"role":"system","content":"..."}, ...]
     * @return 助手回复的纯文本
     */
    @PostMapping("/admin/aiChat.do")
    public Result<String> aiChat(@RequestParam("messagesJson") String messagesJson) {
        try {
            com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
            java.util.List<com.alibaba.dashscope.common.Message> messages = new java.util.ArrayList<>();
            com.fasterxml.jackson.databind.JsonNode arrayNode = mapper.readTree(messagesJson);
            for (com.fasterxml.jackson.databind.JsonNode node : arrayNode) {
                messages.add(com.alibaba.dashscope.common.Message.builder()
                        .role(node.get("role").asText())
                        .content(node.get("content").asText())
                        .build());
            }
            // Add method in AiBo to stream or block fetch from DashScope
            String result = aiBo.chat(messages);
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("AI服务异常: " + e.getMessage());
        }
    }

    /**
     * 获取 AI 短文生成相关配置
     */
    @GetMapping("/admin/getAiStoryConfig.do")
    public Result<java.util.Map<String, Object>> getAiStoryConfig() {
        java.util.Map<String, Object> config = new java.util.HashMap<>();
        int limit = 5;
        SysParam param = sysParamBo.findById("AiStoryConcurrencyLimit");
        if (param != null) {
            limit = Integer.parseInt(param.getParamValue());
        }
        config.put("concurrencyLimit", limit);
        return Result.success(config);
    }

    /**
     * 保存 AI 短文生成相关配置
     */
    @PostMapping("/admin/saveAiStoryConfig.do")
    public Result<String> saveAiStoryConfig(@RequestParam("concurrencyLimit") int concurrencyLimit) throws IllegalAccessException {
        SysParam param = sysParamBo.findById("AiStoryConcurrencyLimit");
        if (param == null) {
            param = new SysParam("AiStoryConcurrencyLimit", String.valueOf(concurrencyLimit), "AI 短文生成并发上限");
            sysParamBo.createEntity(param);
        } else {
            param.setParamValue(String.valueOf(concurrencyLimit));
            sysParamBo.updateEntity(param);
        }
        return Result.success("系统配置保存成功");
    }
}