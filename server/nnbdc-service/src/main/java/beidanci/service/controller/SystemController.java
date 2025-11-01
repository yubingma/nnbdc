package beidanci.service.controller;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.SysDbLogDto;
import beidanci.api.model.DictStatsVo;
import beidanci.api.model.SystemHealthCheckResult;
import beidanci.api.model.SystemHealthFixResult;
import beidanci.service.bo.SysDbLogBo;
import beidanci.service.bo.DictBo;
import beidanci.service.bo.SystemHealthCheckBo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.po.SysParam;
import beidanci.service.util.CdnUtil;
import beidanci.service.util.AliyunResourceUtil;
import beidanci.service.util.AliyunResourceUtil.AccountBalanceInfo;

@RestController
public class SystemController {

    @Autowired
    private SysDbLogBo sysDbLogBo;
    
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

    // ============================================
    // 统一的系统数据版本控制
    // 管理：Levels、DictGroups、Dicts、Sentences、WordImages、WordShortDescChinese
    // 同步方式：增量日志
    // ============================================

    /**
     * 获取系统数据版本号（静态元数据 + UGC内容）
     * 来源：sys_db_version表
     */
    @GetMapping("/getSysDbVersion.do")
    public Result<Integer> getSysDbVersion() {
        int version = sysDbLogBo.getSysDbVersion();
        return Result.success(version);
    }

    /**
     * 获取系统数据增量日志
     * 包含所有系统数据的变更：
     * - 静态数据：Levels、DictGroups、GroupAndDictLinks、Dicts
     * - UGC内容：Sentences、WordImages、WordShortDescChinese
     * 同步方式：增量日志
     */
    @GetMapping("/getNewSysDbLogs.do")
    public Result<List<SysDbLogDto>> getNewSysDbLogs(
            @RequestParam("fromVersion") int fromVersion
    ) {
        List<SysDbLogDto> logs = sysDbLogBo.getNewSysDbLogs(fromVersion);
        return Result.success(logs);
    }

    /**
     * @deprecated 已废弃，使用 getSysDbVersion() 代替
     * 为了兼容旧版本客户端，返回统一的系统数据版本
     */
    @Deprecated
    @GetMapping("/getSystemDbVersion.do")
    public Result<Long> getSystemDbVersion() {
        return Result.success((long) sysDbLogBo.getSysDbVersion());
    }

    /**
     * 获取系统词典列表及其统计信息
     * 返回所有系统词典和每个词典被用户选择的数量
     */
    @GetMapping("/getSystemDictsWithStats.do")
    public Result<List<DictStatsVo>> getSystemDictsWithStats() {
        try {
            List<DictStatsVo> result = dictBo.getSystemDictsWithStats();
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("获取系统词典统计失败: " + e.getMessage());
        }
    }

    /**
     * 获取指定词典的详细统计信息
     */
    @GetMapping("/getDictStats.do")
    public Result<DictStatsVo> getDictStats(@RequestParam("dictId") String dictId) {
        try {
            DictStatsVo result = dictBo.getDictStats(dictId);
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("获取词典统计失败: " + e.getMessage());
        }
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
        try {
            dictBo.updateSystemDict(dictId, name, isReady, visible, popularityLimit);
            return Result.success("词典信息更新成功");
        } catch (Exception e) {
            return Result.fail("更新词典信息失败: " + e.getMessage());
        }
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
        try {
            dictBo.updateDictWord(wordId, spell, shortDesc, longDesc, pronounce, 
                                americaPronounce, britishPronounce, popularity);
            return Result.success("单词信息更新成功");
        } catch (Exception e) {
            return Result.fail("更新单词信息失败: " + e.getMessage());
        }
    }

    /**
     * 从词典中删除单词
     */
    @PostMapping("/removeWordFromDict.do")
    public Result<String> removeWordFromDict(
            @RequestParam("dictId") String dictId,
            @RequestParam("wordId") String wordId
    ) {
        try {
            dictBo.removeWordFromDict(dictId, wordId);
            return Result.success("单词删除成功");
        } catch (Exception e) {
            return Result.fail("删除单词失败: " + e.getMessage());
        }
    }

    // ============================================
    // 系统健康检查相关API
    // ============================================

    /**
     * 检查系统词典完整性
     */
    @GetMapping("/admin/checkSystemDictIntegrity.do")
    public Result<SystemHealthCheckResult> checkSystemDictIntegrity() {
        try {
            SystemHealthCheckResult result = systemHealthCheckBo.checkSystemDictIntegrity();
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("检查系统词典完整性失败: " + e.getMessage());
        }
    }

    /**
     * 检查用户词典完整性
     */
    @GetMapping("/admin/checkUserDictIntegrity.do")
    public Result<SystemHealthCheckResult> checkUserDictIntegrity() {
        try {
            SystemHealthCheckResult result = systemHealthCheckBo.checkUserDictIntegrity();
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("检查用户词典完整性失败: " + e.getMessage());
        }
    }

    /**
     * 检查学习进度合理性
     */
    @GetMapping("/admin/checkLearningProgress.do")
    public Result<SystemHealthCheckResult> checkLearningProgress() {
        try {
            SystemHealthCheckResult result = systemHealthCheckBo.checkLearningProgress();
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("检查学习进度合理性失败: " + e.getMessage());
        }
    }

    /**
     * 检查数据库版本一致性
     */
    @GetMapping("/admin/checkDbVersionConsistency.do")
    public Result<SystemHealthCheckResult> checkDbVersionConsistency() {
        try {
            SystemHealthCheckResult result = systemHealthCheckBo.checkDbVersionConsistency();
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("检查数据库版本一致性失败: " + e.getMessage());
        }
    }

    /**
     * 检查通用词典完整性
     */
    @GetMapping("/admin/checkCommonDictIntegrity.do")
    public Result<SystemHealthCheckResult> checkCommonDictIntegrity() {
        try {
            SystemHealthCheckResult result = systemHealthCheckBo.checkCommonDictIntegrity();
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("检查通用词典完整性失败: " + e.getMessage());
        }
    }

    /**
     * 自动修复系统问题
     */
    @PostMapping("/admin/autoFixSystemIssues.do")
    public Result<SystemHealthFixResult> autoFixSystemIssues(
            @RequestParam("issueTypes") List<String> issueTypes
    ) {
        try {
            SystemHealthFixResult result = systemHealthCheckBo.autoFixSystemIssues(issueTypes);
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("自动修复系统问题失败: " + e.getMessage());
        }
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
    ) {
        try {
            String result = cdnUtil.refreshCache(urls, objectType);
            if ("OK".equals(result)) {
                return Result.success("缓存刷新任务提交成功");
            } else {
                return Result.fail(result);
            }
        } catch (Exception e) {
            return Result.fail("缓存刷新失败: " + e.getMessage());
        }
    }

    /**
     * 获取CDN刷新URL配置
     * @return 配置的URL列表（文件和目录）
     */
    @GetMapping("/admin/getCdnRefreshUrls.do")
    public Result<CdnUrlConfig> getCdnRefreshUrls() {
        try {
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
        } catch (Exception e) {
            return Result.fail("获取配置失败: " + e.getMessage());
        }
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
    ) {
        try {
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
        } catch (Exception e) {
            return Result.fail("保存配置失败: " + e.getMessage());
        }
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
        try {
            AccountBalanceInfo balanceInfo = aliyunResourceUtil.queryAccountBalance();
            if ("查询成功".equals(balanceInfo.getMessage())) {
                return Result.success(balanceInfo);
            } else {
                return Result.fail(balanceInfo.getMessage());
            }
        } catch (Exception e) {
            return Result.fail("查询失败: " + e.getMessage());
        }
    }

    /**
     * 查询阿里云资源包使用情况
     * @return 资源包信息
     */
    @GetMapping("/admin/queryAliyunResourcePackages.do")
    public Result<String> queryAliyunResourcePackages() {
        try {
            String result = aliyunResourceUtil.queryResourcePackageInstances();
            if ("OK".equals(result)) {
                return Result.success("查询成功");
            } else {
                return Result.fail(result);
            }
        } catch (Exception e) {
            return Result.fail("查询失败: " + e.getMessage());
        }
    }
}