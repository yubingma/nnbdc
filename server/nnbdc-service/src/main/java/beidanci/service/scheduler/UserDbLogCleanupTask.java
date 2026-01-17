package beidanci.service.scheduler;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import beidanci.service.bo.UserDbLogBo;

/**
 * 用户数据库日志清理定时任务
 * 每天凌晨3点执行一次，清理30天前的过期日志
 */
@Component
public class UserDbLogCleanupTask {
    private static final Logger log = LoggerFactory.getLogger(UserDbLogCleanupTask.class);

    @Autowired
    private UserDbLogBo userDbLogBo;

    /**
     * 每天凌晨3点执行清理任务
     * cron 表达式：秒 分 时 日 月 周
     * 0 0 3 * * ? 表示每天凌晨3点执行
     */
    @Scheduled(cron = "0 0 3 * * ?")
    public void cleanupOldLogs() {
        try {
            log.info("开始执行用户数据库日志清理任务...");
            int deletedCount = userDbLogBo.cleanOldLogs();
            log.info("用户数据库日志清理任务完成，共删除 {} 条30天前的日志记录", deletedCount);
        } catch (Exception e) {
            log.error("用户数据库日志清理任务执行失败", e);
        }
    }
}
