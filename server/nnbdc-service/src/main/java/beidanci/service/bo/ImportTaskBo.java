package beidanci.service.bo;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.po.ImportTask;

import javax.annotation.PostConstruct;

@Service
@Transactional(rollbackFor = Throwable.class)
public class ImportTaskBo extends BaseBo<ImportTask> {

    @Autowired
    private beidanci.service.dao.ImportTaskDao importTaskDao;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(importTaskDao);
        
        try {
            int updated = jdbcTemplate.update("UPDATE import_task SET status = 'FAILED', " +
                    "results = '{\"error\":\"System abruptly restarted.\"}' " +
                    "WHERE status = 'RUNNING'");
            if (updated > 0) {
                System.out.println("⚠️ [System Startup] Automatically cleaned up " + updated + " zombie RUNNING import tasks.");
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
    
    public void updateProgress(String taskId, int processedCount, String logAppend) {
        ImportTask task = findById(taskId);
        if (task != null) {
            task.setProcessedWords(processedCount);
            if (logAppend != null) {
                String existingLog = task.getLog() != null ? task.getLog() : "";
                task.setLog(existingLog + "\n" + logAppend);
            }
            try {
                updateEntity(task);
            } catch (IllegalAccessException e) {
                throw new RuntimeException(e);
            }
        }
    }
}
