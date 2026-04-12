package beidanci.service.bo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

@Service
public class MaintenanceTaskBo {
    private static final Logger logger = LoggerFactory.getLogger(MaintenanceTaskBo.class);

    @Autowired
    private UserDbLogBo userDbLogBo;

    @Autowired
    private SysDbSyncBo sysDbSyncBo;

    /**
     * 每天凌晨 3:00 执行同步日志清理和数据库维护
     * 1. 删除 10 天前的日志
     * 2. 执行 VACUUM ANALYZE 释放空间并优化索引
     */
    @Scheduled(cron = "0 0 3 * * ?")
    public void dailyMaintenance() {
        logger.info("🌙 [MAINTENANCE] 开始执行例行数据库维护任务...");

        try {
            // 1. 清理用户日志
            int userLogsDeleted = userDbLogBo.cleanOldLogs();
            logger.info("🗑️ [CLEANUP] 已清理旧用户日志，删除行数: {}", userLogsDeleted);

            // 2. 清理系统日志
            int sysLogsDeleted = sysDbSyncBo.cleanOldLogs();
            logger.info("🗑️ [CLEANUP] 已清理旧系统日志，删除行数: {}", sysLogsDeleted);

            // 3. 执行物理维护 (PostgreSQL 特有)
            logger.info("🧹 [VACUUM] 正在对日志表执行 VACUUM ANALYZE...");
            userDbLogBo.vacuumAnalyze();
            sysDbSyncBo.vacuumAnalyze();
            logger.info("✅ [MAINTENANCE] 全天例行维护任务成功完成。");

        } catch (Exception e) {
            logger.error("❌ [ERROR] 数据库维护任务执行失败: {}", e.getMessage(), e);
        }
    }
}
