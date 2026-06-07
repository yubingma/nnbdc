package beidanci.service.controller;

import java.util.List;
import java.io.IOException;
import java.io.File;
import java.util.Date;
import java.util.Map;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.*;
import beidanci.service.bo.*;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.SysParam;
import beidanci.service.util.AliyunResourceUtil;
import beidanci.service.util.AliyunResourceUtil.AccountBalanceInfo;
import beidanci.service.util.PoVoUtils;
import beidanci.service.po.User;
import beidanci.service.util.CdnUtil;
import beidanci.service.util.SysParamUtil;
import beidanci.service.po.DictGroup;
import org.apache.commons.lang3.tuple.Pair;
import beidanci.util.Constants;

@RestController
public class AdminController {
    private static final Logger logger = LoggerFactory.getLogger(AdminController.class);


    @Autowired
    private AiController aiController;

    @Autowired
    private DictBo dictBo;

    @Autowired
    private SentenceBo sentenceBo;

    @Autowired
    private WordBo wordBo;

    @Autowired
    private UserBo userBo;

    @Autowired
    private SystemHealthCheckBo systemHealthCheckBo;

    @Autowired
    private DataSanitizeBo dataSanitizeBo;

    @Autowired
    private CdnUtil cdnUtil;

    @Autowired
    private SysParamBo sysParamBo;

    @Autowired
    private AliyunResourceUtil aliyunResourceUtil;

    @Autowired
    private AiBo aiBo;

    @Autowired
    private DictGroupBo dictGroupBo;

    @Autowired
    private SysParamUtil sysParamUtil;

    @Autowired
    private SysDbSyncBo sysDbSyncBo;

    // ============================================
    // 系统词典管理相关API (管理员接口)
    // ============================================

    @PostMapping("/updateSystemDict.do")
    public Result<String> updateSystemDict(
            @RequestParam("dictId") String dictId,
            @RequestParam("name") String name,
            @RequestParam("isReady") boolean isReady,
            @RequestParam("visible") boolean visible,
            @RequestParam(value = "popularityLimit", required = false) Integer popularityLimit,
            @RequestParam(value = "targetDictGroupId", required = false) String targetDictGroupId,
            @RequestParam(value = "targetGameHallIds", required = false) String targetGameHallIdsJson
    ) {
        List<String> targetGameHallIds = null;
        if (targetGameHallIdsJson != null && !targetGameHallIdsJson.isEmpty()) {
            try {
                com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
                targetGameHallIds = mapper.readValue(targetGameHallIdsJson, new com.fasterxml.jackson.core.type.TypeReference<List<String>>(){});
            } catch (Exception e) {
                return Result.fail("解析游戏大厅ID列表失败: " + e.getMessage());
            }
        }
        dictBo.updateSystemDict(dictId, name, isReady, visible, popularityLimit, targetDictGroupId, targetGameHallIds);
        return Result.success("词典信息更新成功");
    }

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

    @PostMapping("/removeWordFromDict.do")
    public Result<String> removeWordFromDict(
            @RequestParam("dictId") String dictId,
            @RequestParam("wordId") String wordId
    ) {
        dictBo.removeWordFromDict(dictId, wordId);
        return Result.success("单词删除成功");
    }

    // ============================================
    // 词书分组管理API (管理员接口)
    // ============================================

    @PostMapping("/admin/saveDictGroup.do")
    public Result<String> saveDictGroup(
            @RequestParam(value = "id", required = false) String id,
            @RequestParam("name") String name,
            @RequestParam(value = "parentId", required = false) String parentId,
            @RequestParam("displayIndex") int displayIndex
    ) throws IllegalAccessException {
        DictGroup dictGroup;
        if (id != null && !id.isEmpty()) {
            dictGroup = dictGroupBo.findById(id);
            if (dictGroup == null) return Result.fail("分组不存在");
        } else {
            dictGroup = new DictGroup();
        }

        dictGroup.setName(name);
        dictGroup.setDisplayIndex(displayIndex);

        if (parentId != null && !parentId.isEmpty()) {
            DictGroup parent = dictGroupBo.findById(parentId);
            if (parent == null) return Result.fail("父分组不存在");
            dictGroup.setDictGroup(parent);
        } else {
            dictGroup.setDictGroup(null);
        }

        if (id != null && !id.isEmpty()) {
            dictGroupBo.updateEntity(dictGroup);
        } else {
            dictGroupBo.createEntity(dictGroup);
        }

        return Result.success(dictGroup.getId());
    }

    @DeleteMapping("/admin/deleteDictGroup.do")
    public Result<String> deleteDictGroup(@RequestParam("groupId") String groupId) {
        DictGroup dictGroup = dictGroupBo.findById(groupId);
        if (dictGroup == null) return Result.fail("分组不存在");

        dictGroupBo.deleteDictGroupSafely(groupId);
        return Result.success("删除成功");
    }

    @GetMapping("/admin/getAllDictGroups.do")
    public Result<List<DictGroupVo>> getAllDictGroups() {
        List<DictGroup> groups = dictGroupBo.queryAll(null, "displayIndex", "asc", false);
        dictGroupBo.loadDictGroupsAndDictsForDictGroups(groups);
        return Result.success(PoVoUtils.makeVos(groups, DictGroupVo.class, new String[]{"dictGroup"}));
    }

    @GetMapping("/admin/getAllDicts.do")
    public Result<List<DictVo>> getAllDicts() {
        // 只返回系统词书或已分享的词书，过滤掉普通用户的私有词书（如生词本、已掌握等）
        String sql = "SELECT * FROM dict WHERE owner_id = :sysUserId OR is_shared = true ORDER BY name ASC";
        PagedResults<beidanci.service.po.Dict> pagedResults = dictBo.pagedQuery(sql, 1, Integer.MAX_VALUE, Pair.of("sysUserId", Constants.SYS_USER_SYS_ID));
        return Result.success(PoVoUtils.makeVos(pagedResults.getRows(), DictVo.class, null));
    }

    // ============================================
    // 系统健康检查相关API (管理员接口)
    // ============================================

    @GetMapping("/admin/checkSystemDictIntegrity.do")
    public Result<SystemHealthCheckResult> checkSystemDictIntegrity() {
        return Result.success(systemHealthCheckBo.checkSystemDictIntegrity());
    }

    @GetMapping("/admin/checkSysDictMissingFallback.do")
    public Result<SystemHealthCheckResult> checkSysDictMissingFallback() {
        return Result.success(systemHealthCheckBo.checkSystemDictMissingFallback());
    }

    @GetMapping("/admin/checkWordImageIntegrity.do")
    public Result<SystemHealthCheckResult> checkWordImageIntegrity() {
        return Result.success(systemHealthCheckBo.checkWordImageIntegrity());
    }

    @GetMapping("/admin/checkSentenceAudioIntegrity.do")
    public Result<SystemHealthCheckResult> checkSentenceAudioIntegrity() {
        return Result.success(systemHealthCheckBo.checkSentenceAudioIntegrity());
    }

    @GetMapping("/admin/checkUserDictIntegrity.do")
    public Result<SystemHealthCheckResult> checkUserDictIntegrity() {
        return Result.success(systemHealthCheckBo.checkUserDictIntegrity());
    }

    @GetMapping("/admin/checkDbVersionConsistency.do")
    public Result<SystemHealthCheckResult> checkDbVersionConsistency() {
        return Result.success(systemHealthCheckBo.checkDbVersionConsistency());
    }

    @GetMapping("/admin/checkCommonDictIntegrity.do")
    public Result<SystemHealthCheckResult> checkCommonDictIntegrity() {
        return Result.success(systemHealthCheckBo.checkCommonDictIntegrity());
    }

    @GetMapping("/admin/checkUserStudySteps.do")
    public Result<SystemHealthCheckResult> checkUserStudySteps() {
        return Result.success(systemHealthCheckBo.checkUserStudySteps());
    }

    @GetMapping("/admin/checkMissingUserDicts.do")
    public Result<SystemHealthCheckResult> checkMissingUserDicts() {
        return Result.success(systemHealthCheckBo.checkMissingUserDicts());
    }

    @PostMapping("/admin/autoFixSystemIssues.do")
    public Result<SystemHealthFixResult> autoFixSystemIssues(
            @RequestParam("issueTypes") List<String> issueTypes
    ) {
        return Result.success(systemHealthCheckBo.autoFixSystemIssues(issueTypes));
    }

    @PostMapping("/admin/sanitizeData.do")
    public Result<SystemHealthFixResult> sanitizeData() {
        return Result.success(dataSanitizeBo.sanitizeData());
    }

    @PostMapping("/admin/sanitizeWordPopularity.do")
    public Result<SystemHealthFixResult> sanitizeWordPopularity() {
        return Result.success(dataSanitizeBo.sanitizeWordPopularity());
    }

    @GetMapping("/admin/getWordPopularitySanitizeStatus.do")
    public Result<SystemHealthFixResult> getWordPopularitySanitizeStatus() {
        return Result.success(dataSanitizeBo.getWordPopularitySanitizeStatus());
    }

    @PostMapping("/admin/checkDataSanitization.do")
    public Result<SystemHealthCheckResult> checkDataSanitization() {
        return Result.success(dataSanitizeBo.checkDataSanitization());
    }

    // ============================================
    // CDN管理相关API (管理员接口)
    // ============================================

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

    @GetMapping("/admin/getCdnRefreshUrls.do")
    public Result<CdnUrlConfig> getCdnRefreshUrls() {
        String fileUrls = "";
        String dirUrls = "";
        SysParam fileParam = sysParamBo.findById("cdnRefreshFileUrls");
        if (fileParam != null) fileUrls = fileParam.getParamValue();
        SysParam dirParam = sysParamBo.findById("cdnRefreshDirUrls");
        if (dirParam != null) dirUrls = dirParam.getParamValue();
        return Result.success(new CdnUrlConfig(fileUrls, dirUrls));
    }

    @PostMapping("/admin/saveCdnRefreshUrls.do")
    public Result<String> saveCdnRefreshUrls(
            @RequestParam(value = "fileUrls", required = false, defaultValue = "") String fileUrls,
            @RequestParam(value = "dirUrls", required = false, defaultValue = "") String dirUrls
    ) throws IllegalAccessException {
        saveOrUpdateParam("cdnRefreshFileUrls", fileUrls, "CDN文件刷新URL配置");
        saveOrUpdateParam("cdnRefreshDirUrls", dirUrls, "CDN目录刷新URL配置");
        return Result.success("配置保存成功");
    }

    public static class CdnUrlConfig {
        private String fileUrls;
        private String dirUrls;
        public CdnUrlConfig(String fileUrls, String dirUrls) { this.fileUrls = fileUrls; this.dirUrls = dirUrls; }
        public String getFileUrls() { return fileUrls; }
        public void setFileUrls(String fileUrls) { this.fileUrls = fileUrls; }
        public String getDirUrls() { return dirUrls; }
        public void setDirUrls(String dirUrls) { this.dirUrls = dirUrls; }
    }

    // ============================================
    // 阿里云资源查询相关API (管理员接口)
    // ============================================

    @GetMapping("/admin/queryAliyunBalance.do")
    public Result<AccountBalanceInfo> queryAliyunBalance() {
        AccountBalanceInfo balanceInfo = aliyunResourceUtil.queryAccountBalance();
        return "查询成功".equals(balanceInfo.getMessage()) ? Result.success(balanceInfo) : Result.fail(balanceInfo.getMessage());
    }

    @GetMapping("/admin/queryAliyunResourcePackages.do")
    public Result<String> queryAliyunResourcePackages() {
        String result = aliyunResourceUtil.queryResourcePackageInstances();
        return (result.startsWith("{") && result.contains("Instances")) ? Result.success(result) : Result.fail(result);
    }

    // ============================================
    // AI 遗留接口 (管理员接口)
    // ============================================

    @PostMapping(value = "/admin/aiChatStream.do", produces = org.springframework.http.MediaType.TEXT_EVENT_STREAM_VALUE + ";charset=UTF-8")
    public org.springframework.web.servlet.mvc.method.annotation.SseEmitter legacyAiChatStream(
            @RequestParam("messagesJson") String messagesJson,
            @RequestParam(value = "userId", required = false) String userId) {
        if (userId == null || userId.isEmpty()) {
            userId = userBo.getSysUser_sys(false).getId();
        }
        return aiController.aiChatStream(messagesJson, userId);
    }

    @PostMapping("/admin/aiChat.do")
    public Result<String> legacyAiChat(
            @RequestParam("messagesJson") String messagesJson,
            @RequestParam(value = "userId", required = false) String userId) {
        if (userId == null || userId.isEmpty()) {
            userId = userBo.getSysUser_sys(false).getId();
        }
        return aiController.aiChat(messagesJson, userId);
    }

    @GetMapping("/admin/getAiStoryConfig.do")
    public Result<Map<String, Object>> legacyGetAiStoryConfig() {
        return aiController.getAiConfig();
    }

    @PostMapping("/admin/saveAiStoryConfig.do")
    public Result<String> legacySaveAiStoryConfig(
            @RequestParam("concurrencyLimit") int concurrencyLimit,
            @RequestParam(value = "aiChatGlobalLimit", defaultValue = "20") int aiChatGlobalLimit,
            @RequestParam(value = "aiChatUserLimit", defaultValue = "2") int aiChatUserLimit,
            @RequestParam(value = "aiChatUserDailyLimit", defaultValue = "100") int aiChatUserDailyLimit) throws IllegalAccessException {
        return aiController.saveAiConfig(concurrencyLimit, aiChatGlobalLimit, aiChatUserLimit, aiChatUserDailyLimit);
    }

    // ============================================
    // 管理员例句管理API
    // ============================================

    @GetMapping("/admin/getWordSentences.do")
    public Result<List<SentenceVo>> getWordSentences(@RequestParam("wordId") String wordId) {
        List<SentenceDto> dtos = sentenceBo.getSentencesByWordId(wordId);
        List<SentenceVo> vos = dtos.stream().map(dto -> {
            SentenceVo vo = new SentenceVo();
            vo.setId(dto.getId());
            vo.setEnglish(dto.getEnglish());
            vo.setChinese(dto.getChinese());
            vo.setTheType(dto.getTheType());
            vo.setEnglishDigest(dto.getEnglishDigest());
            vo.setHandCount(dto.getHandCount());
            vo.setFootCount(dto.getFootCount());
            if (dto.getAuthorId() != null) {
                UserVo author = new UserVo();
                author.setId(dto.getAuthorId());
                vo.setAuthor(author);
            }
            return vo;
        }).collect(Collectors.toList());
        return Result.success(vos);
    }

    @PostMapping("/admin/updateSentence.do")
    public Result<String> updateSentence(
            @RequestParam("id") String id,
            @RequestParam("english") String english,
            @RequestParam("chinese") String chinese) throws IllegalAccessException, IOException, InvalidMeaningFormatException, EmptySpellException, ParseException {
        sentenceBo.updateSentence(id, english, chinese);
        return Result.success("例句更新成功");
    }

    @PostMapping("/admin/regenerateWordPronunciation.do")
    public Result<String> regenerateWordPronunciation(@RequestParam("wordId") String wordId) {
        try {
            wordBo.regeneratePronunciation(wordId);
            return Result.success("发音重新生成成功");
        } catch (Exception e) {
            return Result.fail("发音重新生成失败: " + e.getMessage());
        }
    }

    @PostMapping("/admin/deleteSentence.do")
    public Result<String> deleteSentence(@RequestParam("id") String id) throws InvalidMeaningFormatException, EmptySpellException, ParseException, IOException {
        String sysUserId = userBo.getSysUser_sys(false).getId();
        Result<Void> res = sentenceBo.deleteSentence(id, null, sysUserId);
        return res.isSuccess() ? Result.success("例句删除成功") : Result.fail(res.getMsg());
    }

    // ============================================
    // 系统参数管理API (管理员接口)
    // ============================================

    @GetMapping("/admin/getAllSysParams.do")
    public Result<List<SysParam>> getAllSysParams() {
        List<SysParam> dbParams = sysParamBo.queryAll(null, "paramName", "asc", false);
        return Result.success(sysParamUtil.mergeWithDefaults(dbParams));
    }

    @PostMapping("/admin/saveSysParam.do")
    public Result<String> saveSysParam(
            @RequestParam("paramName") String paramName,
            @RequestParam("paramValue") String paramValue,
            @RequestParam(value = "comment", required = false) String comment
    ) throws IllegalAccessException {
        saveOrUpdateParam(paramName, paramValue, comment);
        return Result.success("参数保存成功");
    }

    @PostMapping("/admin/deleteSysParam.do")
    public Result<String> deleteSysParam(@RequestParam("paramName") String paramName) {
        sysParamBo.deleteById(paramName);
        return Result.success("参数删除成功");
    }

    @PostMapping("/admin/reGenerateSystemSyncLogs.do")
    public Result<String> reGenerateSystemSyncLogs() {
        sysDbSyncBo.reGenerateSystemDataLogs();
        return Result.success("系统同步日志重新生成成功");
    }

    // ============================================
    // 用户管理相关API (管理员接口)
    // ============================================

    @GetMapping("/admin/searchUsers.do")
    public Result<PagedResults<UserVo>> searchUsers(
            @RequestParam(required = false) String keyword,
            @RequestParam(defaultValue = "1") int pageNo,
            @RequestParam(defaultValue = "20") int pageSize,
            @RequestParam(required = false) Integer filterType) throws IllegalAccessException {
        PagedResults<User> pagedResults = userBo.searchUsers(keyword, pageNo, pageSize, filterType);
        List<User> users = pagedResults.getRows();
        List<UserVo> userVos = PoVoUtils.makeVos(users, UserVo.class,
                new String[] { "invitedBy", "StudyGroupVo.creator", "StudyGroupVo.users",
                        "StudyGroupVo.managers", "studyGroupPosts", "userGames" });
        return Result.success(new PagedResults<>(pagedResults.getTotal(), userVos));
    }

    @PostMapping("/admin/updateAdminPermission.do")
    public Result<Void> updateAdminPermission(
            @RequestParam String userId,
            @RequestParam(required = false) Boolean isAdmin,
            @RequestParam(required = false) Boolean isSuperAdmin,
            @RequestParam(required = false) Boolean isInputor) throws IllegalAccessException {
        return userBo.updateAdminPermission(userId, isAdmin, isSuperAdmin, isInputor);
    }

    @PostMapping("/admin/updatePremiumOverride.do")
    public Result<Void> updatePremiumOverride(
            @RequestParam String userId,
            @RequestParam Boolean enabled,
            @RequestParam(required = false) String reason,
            @RequestParam(required = false) String duration) throws IllegalAccessException {
        User user = userBo.findById(userId);
        if (user == null) return Result.fail("用户不存在");

        user.setPremiumOverrideEnabled(enabled);
        user.setPremiumOverrideUpdateTime(new Date());
        user.setPremiumOverrideReason(reason);
        user.setPremiumOverrideDuration(duration);

        userBo.updateEntity(user);
        userBo.logUserUpdateForSync(user);
        return Result.success(null);
    }

    @org.springframework.web.bind.annotation.DeleteMapping("/admin/deleteUser.do")
    public Result<Void> deleteUser(@RequestParam String userId) throws IllegalAccessException {
        User user = userBo.findById(userId);
        if (user == null) return Result.fail("用户不存在");
        if (user.getIsSysUser() != null && Boolean.TRUE.equals(user.getIsSysUser())) return Result.fail("不能删除系统用户");
        userBo.deleteUser(user);
        return Result.success(null);
    }

    @GetMapping("/admin/getUserById.do")
    public Result<UserVo> getUserById(@RequestParam String userId) throws IllegalAccessException {
        User user = userBo.findById(userId);
        if (user == null) return Result.fail("用户不存在");
        UserVo userVo = PoVoUtils.makeVo(user, UserVo.class,
                new String[] { "invitedBy", "StudyGroupVo.creator", "StudyGroupVo.users",
                        "StudyGroupVo.managers", "studyGroupPosts", "userGames" });
        return Result.success(userVo);
    }

    // ============================================
    // PDF 单词提取相关 API (管理员接口)
    // ============================================

    @SuppressWarnings("null")
    @PostMapping(value = "/admin/pdf/extractWords.do", produces = org.springframework.http.MediaType.TEXT_EVENT_STREAM_VALUE)
    public org.springframework.web.servlet.mvc.method.annotation.SseEmitter extractWordsFromPdf(
            @RequestParam("file") org.springframework.web.multipart.MultipartFile file,
            @RequestParam(value = "startPage", required = false) Integer startPage
    ) {
        // 使用文件名和大小作为唯一标识（简单且能区分不同文件）
        String fileName = file.getOriginalFilename();
        if (fileName == null) fileName = "unknown_" + System.currentTimeMillis();
        String taskId = fileName + "_" + file.getSize();
        
        beidanci.service.bo.AiBo.ExtractionTask task = aiBo.getExtractionTask(taskId);
        if (task == null) {
            try {
                File localTempFile = File.createTempFile("tantan_extract_", ".pdf");
                file.transferTo(localTempFile);
                task = aiBo.getOrCreateExtractionTask(taskId, fileName, file.getSize(), localTempFile);
                if (startPage != null && startPage > 0) {
                    task.processedPages = startPage - 1;
                }
            } catch (IOException e) {
                logger.error("Failed to create temp file", e);
                org.springframework.web.servlet.mvc.method.annotation.SseEmitter errorEmitter = new org.springframework.web.servlet.mvc.method.annotation.SseEmitter(60000L);
                try {
                    errorEmitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("error").data("服务器内部错误: 无法保存上传文件"));
                    errorEmitter.complete();
                } catch (IOException ignore) {}
                return errorEmitter;
            }
        }
        
        return attachToTask(task);
    }

    @GetMapping(value = "/admin/pdf/syncTask.do", produces = org.springframework.http.MediaType.TEXT_EVENT_STREAM_VALUE)
    public org.springframework.web.servlet.mvc.method.annotation.SseEmitter syncTask(@RequestParam("taskId") String taskId) {
        beidanci.service.bo.AiBo.ExtractionTask task = aiBo.getExtractionTask(taskId);
        if (task == null) {
            org.springframework.web.servlet.mvc.method.annotation.SseEmitter errorEmitter = new org.springframework.web.servlet.mvc.method.annotation.SseEmitter(60000L);
            try {
                errorEmitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("error").data("任务不存在或已过期"));
                errorEmitter.complete();
            } catch (IOException ignore) {}
            return errorEmitter;
        }
        return attachToTask(task);
    }

    @SuppressWarnings("null")
    private org.springframework.web.servlet.mvc.method.annotation.SseEmitter attachToTask(final beidanci.service.bo.AiBo.ExtractionTask finalTask) {
        final org.springframework.web.servlet.mvc.method.annotation.SseEmitter emitter = 
                new org.springframework.web.servlet.mvc.method.annotation.SseEmitter(3600000L * 12); // 12 hours timeout
        
        // 1. 定义监听器 (增加页码支持)
        final java.util.function.BiConsumer<Integer, String> pageListener = (pageIndex, pageWords) -> {
            try {
                emitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("page_start").data(pageIndex.toString()));
                for (String wordLine : pageWords.split("\n")) {
                    if (!wordLine.trim().isEmpty()) {
                        emitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("page").data(wordLine));
                    }
                }
            } catch (Exception ignore) {}
        };

        final java.util.function.BiConsumer<Integer, String> pageErrorListener = (pageIndex, errorMsg) -> {
            try {
                emitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("page_error").data(pageIndex + "|" + errorMsg));
            } catch (Exception ignore) {}
        };

        final java.util.function.Consumer<String> errorListener = error -> {
            try {
                emitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("error").data("PDF 解析失败: " + error));
                emitter.complete();
            } catch (Exception ignore) {}
        };

        final java.util.function.Consumer<String> warningListener = warning -> {
            try {
                emitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("warning").data(warning));
            } catch (Exception ignore) {}
        };

        final Runnable completionListener = () -> {
            try {
                emitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("complete").data("解析完成"));
                emitter.complete();
            } catch (Exception ignore) {}
        };

        // 2. 注册清理逻辑
        emitter.onCompletion(() -> {
            finalTask.listeners.remove(pageListener);
            finalTask.errorListeners.remove(errorListener);
            finalTask.warningListeners.remove(warningListener);
            finalTask.pageErrorListeners.remove(pageErrorListener);
            finalTask.completionListeners.remove(completionListener);
        });
        emitter.onTimeout(() -> {
            finalTask.listeners.remove(pageListener);
            finalTask.errorListeners.remove(errorListener);
            finalTask.warningListeners.remove(warningListener);
            finalTask.pageErrorListeners.remove(pageErrorListener);
            finalTask.completionListeners.remove(completionListener);
        });
        emitter.onError(e -> {
            finalTask.listeners.remove(pageListener);
            finalTask.errorListeners.remove(errorListener);
            finalTask.warningListeners.remove(warningListener);
            finalTask.pageErrorListeners.remove(pageErrorListener);
            finalTask.completionListeners.remove(completionListener);
        });

        // 3. 推送已有结果
        try {
            // 推送成功结果
            for (int i = 0; i < finalTask.pageResults.size(); i++) {
                pageListener.accept(i + 1, finalTask.pageResults.get(i));
            }

            // 推送失败结果
            for (java.util.Map.Entry<Integer, String> entry : finalTask.failedPages.entrySet()) {
                pageErrorListener.accept(entry.getKey(), entry.getValue());
            }

            if (finalTask.isFinished) {
                emitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("complete").data("解析完成"));
                emitter.complete();
                return emitter;
            }

            if (finalTask.error != null) {
                emitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("error").data("PDF 解析失败: " + finalTask.error));
                emitter.complete();
                return emitter;
            }
        } catch (Exception e) {
            logger.error("Failed to send existing results for taskId: " + finalTask.taskId, e);
        }

        // 4. 挂载新监听器
        finalTask.listeners.add(pageListener);
        finalTask.errorListeners.add(errorListener);
        finalTask.warningListeners.add(warningListener);
        finalTask.pageErrorListeners.add(pageErrorListener);
        finalTask.completionListeners.add(completionListener);

        // 5. 如果任务未启动，则异步启动
        if (!finalTask.isStarted) {
            finalTask.isStarted = true;
            new Thread(() -> {
                aiBo.parsePdfToWordsTask(finalTask.pdfFile, finalTask);
            }).start();
        }

        return emitter;
    }

    @GetMapping("/admin/pdf/tasks.do")
    public Result<List<Map<String, Object>>> getPdfExtractionTasks() {
        List<AiBo.ExtractionTask> tasks = aiBo.getAllExtractionTasks();
        List<Map<String, Object>> result = tasks.stream().map(task -> {
            Map<String, Object> map = new java.util.HashMap<>();
            map.put("taskId", task.taskId);
            map.put("fileName", task.fileName);
            map.put("fileSize", task.fileSize);
            map.put("processedPages", task.processedPages);
            map.put("totalPages", task.totalPages);
            map.put("isFinished", task.isFinished);
            map.put("isStopped", task.isStopped);
            map.put("isStarted", task.isStarted);
            map.put("error", task.error);
            map.put("startTime", task.startTime);
            map.put("lastAccessTime", task.lastAccessTime);
            map.put("resultCount", task.pageResults.size());
            map.put("failedPages", task.failedPages);
            return map;
        }).collect(Collectors.toList());
        return Result.success(result);
    }

    @PostMapping("/admin/pdf/stopTask.do")
    public Result<String> stopPdfExtractionTask(@RequestParam("taskId") String taskId) {
        if (aiBo.stopExtractionTask(taskId)) {
            return Result.success("任务已成功停止");
        } else {
            return Result.fail("找不到指定的任务");
        }
    }

    @PostMapping("/admin/pdf/removeTask.do")
    public Result<String> removePdfExtractionTask(@RequestParam("taskId") String taskId) {
        if (aiBo.removeExtractionTask(taskId)) {
            return Result.success("任务已成功从内存中移除");
        } else {
            return Result.fail("找不到指定的任务");
        }
    }

    @PostMapping("/admin/pdf/resumeTask.do")
    public Result<String> resumePdfExtractionTask(@RequestParam("taskId") String taskId, 
                                                @RequestParam(value = "startPage", required = false) Integer startPage) {
        aiBo.resumeExtractionTask(taskId, startPage);
        return Result.success("任务已尝试从第 " + (startPage != null ? startPage : "上次失败处") + " 页恢复运行");
    }

    private void saveOrUpdateParam(String name, String value, String comment) throws IllegalAccessException {
        SysParam param = sysParamBo.findById(name);
        if (param == null) {
            param = new SysParam(name, value, comment);
            sysParamBo.createEntity(param);
        } else {
            param.setParamValue(value);
            if (comment != null) param.setComment(comment);
            sysParamBo.updateEntity(param);
        }
    }
}
