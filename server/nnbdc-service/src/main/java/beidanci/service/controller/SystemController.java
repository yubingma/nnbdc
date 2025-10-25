package beidanci.service.controller;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.SysDbLogDto;
import beidanci.service.bo.SysDbLogBo;

@RestController
public class SystemController {

    @Autowired
    private SysDbLogBo sysDbLogBo;

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

}
