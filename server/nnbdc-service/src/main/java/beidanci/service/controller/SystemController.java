package beidanci.service.controller;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.SysDbLogDto;
import beidanci.api.model.DictStatsDto;
import beidanci.service.bo.SysDbLogBo;
import beidanci.service.bo.DictBo;

@RestController
public class SystemController {

    @Autowired
    private SysDbLogBo sysDbLogBo;
    
    @Autowired
    private DictBo dictBo;

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
    public Result<List<DictStatsDto>> getSystemDictsWithStats() {
        try {
            List<DictStatsDto> result = dictBo.getSystemDictsWithStats();
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("获取系统词典统计失败: " + e.getMessage());
        }
    }

    /**
     * 获取指定词典的详细统计信息
     */
    @GetMapping("/getDictStats.do")
    public Result<DictStatsDto> getDictStats(@RequestParam("dictId") String dictId) {
        try {
            DictStatsDto result = dictBo.getDictStats(dictId);
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

}
