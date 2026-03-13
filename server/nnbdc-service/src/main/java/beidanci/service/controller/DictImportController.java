package beidanci.service.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import beidanci.api.Result;
import beidanci.service.bo.DictImportBo;
import beidanci.service.bo.ImportTaskBo;
import beidanci.service.po.ImportTask;
import beidanci.service.po.User;

import beidanci.service.util.JsonUtils;

import java.util.Date;

@RestController
@RequestMapping("/import")
public class DictImportController {

    @Autowired
    private DictImportBo dictImportBo;

    @Autowired
    private ImportTaskBo importTaskBo;

    /**
     * 提交一个导入任务
     *
     * @param userId 用户ID
     * @param config 导入配置 (JSON)
     * @return 任务ID
     */
    @PostMapping("/submit")
    public Result<String> submitTask(@RequestBody ImportRequest request) {
        ImportTask task = new ImportTask();
        User owner = new User();
        owner.setId(request.getOwnerId());
        task.setOwner(owner);
        task.setConfig(request.getConfig());
        task.setStatus("PENDING");
        task.setFileName(request.getFileName() != null ? request.getFileName() : "unnamed_import_" + System.currentTimeMillis());
        task.setCreateTime(new Date());
        task.setUpdateTime(new Date());

        // 同步校验配置格式
        try {
            JsonUtils.parseMap(request.getConfig());
        } catch (Exception e) {
            return Result.fail("配置格式有误: " + e.getMessage());
        }

        importTaskBo.createEntity(task);
        
        // 异步执行
        dictImportBo.executeImportTask(task.getId());
        
        return Result.success(task.getId());
    }

    @GetMapping("/getTaskStatus")
    public Result<ImportTask> getTaskStatus(@RequestParam String taskId) {
        ImportTask task = importTaskBo.findById(taskId);
        if (task == null) {
            return Result.fail("任务不存在");
        }
        return Result.success(task);
    }

    public static class ImportRequest {
        private String ownerId;
        private String fileName;
        private String config;

        public String getOwnerId() { return ownerId; }
        public void setOwnerId(String ownerId) { this.ownerId = ownerId; }
        public String getFileName() { return fileName; }
        public void setFileName(String fileName) { this.fileName = fileName; }
        public String getConfig() { return config; }
        public void setConfig(String config) { this.config = config; }
    }
}
