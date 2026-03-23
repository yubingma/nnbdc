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

    @Autowired
    private beidanci.service.bo.DictBo dictBo;

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

    @PostMapping("/cancel")
    public Result<String> cancelTask(@RequestParam String taskId) {
        ImportTask task = importTaskBo.findById(taskId);
        if (task == null) {
            return Result.fail("任务不存在");
        }
        if ("RUNNING".equals(task.getStatus()) || "PENDING".equals(task.getStatus())) {
            task.setStatus("CANCELED");
            try {
                importTaskBo.updateEntity(task);
            } catch (IllegalAccessException e) {
                return Result.fail("取消失败: " + e.getMessage());
            }
            return Result.success("已发送取消指令");
        }
        return Result.fail("只有 RUNNING 或 PENDING 状态的任务可以被取消");
    }

    @GetMapping("/getTaskStatus")
    public Result<ImportTask> getTaskStatus(@RequestParam String taskId) {
        ImportTask task = importTaskBo.findById(taskId);
        if (task == null) {
            return Result.fail("任务不存在");
        }
        return Result.success(task);
    }

    @PostMapping("/deleteSystemDict")
    public Result<String> deleteSystemDict(@RequestParam String dictId) {
        try {
            // Because this is a destructive operation, we just call the DictBo locally 
            // without creating a Task since memory clearing happens synchronously better anyway.
            beidanci.service.po.Dict dict = dictBo.findById(dictId);
            if (dict == null) {
                return Result.fail("找不到系统词库");
            }
            if (!beidanci.util.Constants.SYS_USER_SYS_ID.equals(dict.getOwner().getId())) {
                return Result.fail("只限删除System(管理员)名下的系统公共词典!");
            }
            dictBo.deleteSystemDictSafely(dictId);
            return Result.success("删除成功");
        } catch (Exception e) {
            return Result.fail("删除失败: " + e.getMessage());
        }
    }

    @GetMapping("/searchSystemDicts")
    public Result<java.util.List<java.util.Map<String, Object>>> searchSystemDicts(@RequestParam(required = false) String keyword) {
        try {
            return Result.success(dictBo.searchSystemDicts(keyword));
        } catch (Exception e) {
            return Result.fail("查询失败: " + e.getMessage());
        }
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
