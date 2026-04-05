package beidanci.service.controller;

import java.util.List;
import java.io.IOException;
import java.util.Map;
import java.util.stream.Collectors;

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
import beidanci.service.util.CdnUtil;

@RestController
public class SystemController {

    @Autowired
    private AiController aiController;


    
    @Autowired
    private DictBo dictBo;

    @Autowired
    private SentenceBo sentenceBo;

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
     * 检查单词配图完整性
     */
    @GetMapping("/admin/checkWordImageIntegrity.do")
    public Result<SystemHealthCheckResult> checkWordImageIntegrity() {
        SystemHealthCheckResult result = systemHealthCheckBo.checkWordImageIntegrity();
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
     * 阿里云AI对话 (流式输出) - 遗留接口
     */
    @PostMapping(value = "/admin/aiChatStream.do", produces = org.springframework.http.MediaType.TEXT_EVENT_STREAM_VALUE + ";charset=UTF-8")
    public org.springframework.web.servlet.mvc.method.annotation.SseEmitter legacyAiChatStream(
            @RequestParam("messagesJson") String messagesJson,
            @RequestParam("userId") String userId) {
        // 直接调用 AiController 的逻辑或重复逻辑。为了解耦，我们在这里重新实现或调用注入的 AiController (后者较少见)。
        // 既然我们要在 SystemController 保留代码，就直接写在这里。
        return aiController.aiChatStream(messagesJson, userId);
    }

    /**
     * 阿里云AI对话 - 遗留接口
     */
    @PostMapping("/admin/aiChat.do")
    public Result<String> legacyAiChat(
            @RequestParam("messagesJson") String messagesJson,
            @RequestParam("userId") String userId) {
        return aiController.aiChat(messagesJson, userId);
    }

    /**
     * 生成 AI 短文 - 遗留接口
     */
    @PostMapping("/generateAiShortStory.do")
    public Result<String> legacyGenerateAiShortStory(
            @RequestParam("wordsJson") String wordsJson,
            @RequestParam("userId") String userId) {
        return aiController.generateAiShortStory(wordsJson, userId);
    }

    /**
     * 获取 AI 相关配置 - 遗留接口
     */
    @GetMapping("/admin/getAiStoryConfig.do")
    public Result<Map<String, Object>> legacyGetAiStoryConfig() {
        return aiController.getAiConfig();
    }

    /**
     * 保存 AI 相关配置 - 遗留接口
     */
    @PostMapping("/admin/saveAiStoryConfig.do")
    public Result<String> legacySaveAiStoryConfig(
            @RequestParam("concurrencyLimit") int concurrencyLimit,
            @RequestParam(value = "aiChatGlobalLimit", defaultValue = "20") int aiChatGlobalLimit,
            @RequestParam(value = "aiChatUserLimit", defaultValue = "2") int aiChatUserLimit,
            @RequestParam(value = "aiChatUserDailyLimit", defaultValue = "100") int aiChatUserDailyLimit) throws IllegalAccessException {
        return aiController.saveAiConfig(concurrencyLimit, aiChatGlobalLimit, aiChatUserLimit, aiChatUserDailyLimit);
    }

    /**
     * 获取指定单词的所有例句 (管理员接口)
     */
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

    /**
     * 更新单词例句 (管理员接口)
     */
    @PostMapping("/admin/updateSentence.do")
    public Result<String> updateSentence(
            @RequestParam("id") String id,
            @RequestParam("english") String english,
            @RequestParam("chinese") String chinese) throws IllegalAccessException, IOException, InvalidMeaningFormatException, EmptySpellException, ParseException {
        sentenceBo.updateSentence(id, english, chinese);
        return Result.success("例句更新成功");
    }

    /**
     * 从系统后台删除例句 (管理员接口)
     */
    @PostMapping("/admin/deleteSentence.do")
    public Result<String> deleteSentence(@RequestParam("id") String id) throws InvalidMeaningFormatException, EmptySpellException, ParseException, IOException {
        String sysUserId = userBo.getSysUser_sys(false).getId();
        Result<Void> res = sentenceBo.deleteSentence(id, null, sysUserId);
        if (res.isSuccess()) {
            return Result.success("例句删除成功");
        } else {
            return Result.fail(res.getMsg());
        }
    }

    /**
     * 获取所有系统参数
     */
    @GetMapping("/admin/getAllSysParams.do")
    public Result<List<SysParam>> getAllSysParams() {
        List<SysParam> params = sysParamBo.queryAll(null, "paramName", "asc", false);
        return Result.success(params);
    }

    /**
     * 保存系统参数
     */
    @PostMapping("/admin/saveSysParam.do")
    public Result<String> saveSysParam(
            @RequestParam("paramName") String paramName,
            @RequestParam("paramValue") String paramValue,
            @RequestParam(value = "comment", required = false) String comment
    ) throws IllegalAccessException {
        SysParam param = sysParamBo.findById(paramName);
        if (param == null) {
            param = new SysParam(paramName, paramValue, comment);
            sysParamBo.createEntity(param);
        } else {
            param.setParamValue(paramValue);
            if (comment != null) {
                param.setComment(comment);
            }
            sysParamBo.updateEntity(param);
        }
        return Result.success("参数保存成功");
    }

    /**
     * 删除系统参数
     */
    @PostMapping("/admin/deleteSysParam.do")
    public Result<String> deleteSysParam(@RequestParam("paramName") String paramName) {
        sysParamBo.deleteById(paramName);
        return Result.success("参数删除成功");
    }
}
