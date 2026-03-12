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
import java.util.Map;

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
    @PostMapping("/submitTask.do")
    public Result<String> submitTask(@RequestParam String userId, @RequestBody String config) {
        ImportTask task = new ImportTask();
        User owner = new User();
        owner.setId(userId);
        task.setOwner(owner);
        task.setConfig(config);
        task.setStatus("PENDING");
        task.setCreateTime(new Date());
        task.setUpdateTime(new Date());
        
        // 尝试从文件名（如果有）设置
        Map<String, Object> configMap = JsonUtils.parseMap(config);
        if (configMap.containsKey("fileName")) {
            task.setFileName((String) configMap.get("fileName"));
        } else {
            task.setFileName("unnamed_import_" + System.currentTimeMillis());
        }

        importTaskBo.createEntity(task);
        
        // 异步执行
        dictImportBo.executeImportTask(task.getId());
        
        return Result.success(task.getId());
    }

    /**
     * 查询任务状态
     */
    @GetMapping("/getTaskStatus.do")
    public Result<ImportTask> getTaskStatus(@RequestParam String taskId) {
        ImportTask task = importTaskBo.findById(taskId);
        if (task == null) {
            return Result.fail("任务不存在");
        }
        return Result.success(task);
    }
}
