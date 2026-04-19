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
    private CdnUtil cdnUtil;

    @Autowired
    private SysParamBo sysParamBo;

    @Autowired
    private AliyunResourceUtil aliyunResourceUtil;

    @Autowired
    private AiBo aiBo;

    @Autowired
    private SysParamUtil sysParamUtil;

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

    @PostMapping(value = "/admin/pdf/extractWords.do", produces = org.springframework.http.MediaType.TEXT_EVENT_STREAM_VALUE)
    public org.springframework.web.servlet.mvc.method.annotation.SseEmitter extractWordsFromPdf(
            @RequestParam("file") org.springframework.web.multipart.MultipartFile file
    ) {
        org.springframework.web.servlet.mvc.method.annotation.SseEmitter emitter = new org.springframework.web.servlet.mvc.method.annotation.SseEmitter(600000L); // 10 minutes timeout
        
        if (file.isEmpty()) {
            try {
                emitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("error").data("上传文件不能为空"));
                emitter.complete();
            } catch (IOException e) {
                logger.error("SSE error", e);
            }
            return emitter;
        }

        new Thread(() -> {
            File tempFile = null;
            try {
                tempFile = File.createTempFile("tantan_extract_", ".pdf");
                file.transferTo(tempFile);

                aiBo.parsePdfToWordsStream(tempFile, pageWords -> {
                    try {
                        if (pageWords != null) {
                            emitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("page").data(pageWords));
                        }
                    } catch (IOException e) {
                        logger.error("Failed to send page words via SSE", e);
                    }
                });
                emitter.complete();
            } catch (Exception e) {
                try {
                    emitter.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event().name("error").data("PDF 解析失败: " + e.getMessage()));
                    emitter.completeWithError(e);
                } catch (IOException ex) {
                    logger.error("SSE error during exception handling", ex);
                }
            } finally {
                if (tempFile != null && tempFile.exists()) {
                    tempFile.delete();
                }
            }
        }).start();

        return emitter;
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
