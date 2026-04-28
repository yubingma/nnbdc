package beidanci.service.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import beidanci.api.Result;
import beidanci.service.bo.DictImportBo;
import beidanci.service.bo.ImportTaskBo;
import beidanci.service.bo.DictBo;
import beidanci.service.po.ImportTask;
import beidanci.service.po.User;
import beidanci.service.po.Dict;
import beidanci.util.Constants;
import java.util.*;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import beidanci.service.util.JsonUtils;


@RestController
@RequestMapping("/import")
public class DictImportController {

    @Autowired
    private org.springframework.jdbc.core.JdbcTemplate jdbcTemplate;

    @Autowired
    private DictImportBo dictImportBo;


    @Autowired
    private ImportTaskBo importTaskBo;

    @Autowired
    private DictBo dictBo;

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
            Dict dict = dictBo.findById(dictId);
            if (dict == null) {
                return Result.fail("找不到系统词库");
            }
            if (!Constants.SYS_USER_SYS_ID.equals(dict.getOwner().getId())) {
                return Result.fail("只限删除System(管理员)名下的系统公共词典!");
            }
            dictBo.deleteSystemDictSafely(dictId);
            return Result.success("删除成功");
        } catch (Exception e) {
            return Result.fail("删除失败: " + e.getMessage());
        }
    }

    @GetMapping("/searchSystemDicts")
    public Result<List<Map<String, Object>>> searchSystemDicts(@RequestParam(required = false) String keyword) {
        try {
            return Result.success(dictBo.searchSystemDicts(keyword));
        } catch (Exception e) {
            return Result.fail("查询失败: " + e.getMessage());
        }
    }
    @SuppressWarnings("unchecked")
    @PostMapping("/batch")
    public Result<String> batchSubmit(@RequestParam String dirPath,
                                      @RequestParam(required = false) List<String> defaultDictGroupIds,
                                      @RequestParam(required = false) List<String> defaultGameHallIds) {

        String batchId = "BATCH_" + System.currentTimeMillis();
        try {
            File metaFile = new File(dirPath, "meta.json");

            if (!metaFile.exists()) {
                return Result.fail("找不到元数据配置文件 meta.json 于目录: " + dirPath);
            }

            String metaJson = new String(Files.readAllBytes(metaFile.toPath()), StandardCharsets.UTF_8);
            Map<String, Object> metaMap = JsonUtils.parseMap(metaJson);

            List<Map<String, Object>> books = (List<Map<String, Object>>) metaMap.get("books");
            if (books == null || books.isEmpty()) {
                return Result.fail("meta.json 中没有配置需要导入的词书 books");
            }

            // 1. 首先验证是否所有的词书都不存在同名词书
            for (Map<String, Object> book : books) {
                String dictName = (String) book.get("dictName");
                if (dictName != null && !dictName.trim().isEmpty()) {
                    Dict existingDict = dictBo.findByName(dictName.trim());
                    if (existingDict != null) {
                        return Result.fail("批量导入失败：同名词书「" + dictName + "」已存在，所有任务不予创建！");
                    }
                }
            }

            // 获取全局通用配置
            boolean isSystemImport = (boolean) metaMap.getOrDefault("isSystemImport", false);
            boolean generateWordImage = (boolean) metaMap.getOrDefault("generateWordImage", false);
            boolean generateShuffledVersion = (boolean) metaMap.getOrDefault("generateShuffledVersion", false);
            String globalGroupId = (String) metaMap.get("targetDictGroupId");
            List<String> globalGroupIds = (List<String>) metaMap.get("targetDictGroupIds");
            List<String> globalGameHallIds = (List<String>) metaMap.get("targetGameHallIds");

            if ((globalGroupId == null || globalGroupId.trim().isEmpty()) && (globalGroupIds == null || globalGroupIds.isEmpty())) {
                globalGroupIds = defaultDictGroupIds;
            }
            if (globalGameHallIds == null || globalGameHallIds.isEmpty()) {
                globalGameHallIds = defaultGameHallIds;
            }

            int createdCount = 0;

            // 2. 校验通过后，开始循环创建任务
            for (Map<String, Object> book : books) {
                String fileName = (String) book.get("fileName");
                String dictName = (String) book.get("dictName");
                String domain = (String) book.get("domain");
                String description = (String) book.get("description");
                String targetDictGroupId = (String) book.get("targetDictGroupId");
                List<String> targetDictGroupIds = (List<String>) book.get("targetDictGroupIds");
                List<String> targetGameHallIds = (List<String>) book.get("targetGameHallIds");

                if ((targetDictGroupId == null || targetDictGroupId.trim().isEmpty()) && (targetDictGroupIds == null || targetDictGroupIds.isEmpty())) {
                    targetDictGroupIds = globalGroupIds;
                }
                if (targetGameHallIds == null || targetGameHallIds.isEmpty()) {
                    targetGameHallIds = globalGameHallIds;
                }


                // 读取对应的 TXT 文件提取单词
                File txtFile = new File(dirPath, fileName);
                if (!txtFile.exists()) {
                    return Result.fail("找不到对应的词书物理 TXT 文件: " + fileName);
                }

                List<String> words = new ArrayList<>();
                try (BufferedReader reader = new BufferedReader(new FileReader(txtFile))) {
                    String line;
                    while ((line = reader.readLine()) != null) {
                        String trimmed = line.trim();
                        if (trimmed.isEmpty() || trimmed.startsWith("#")) continue;
                        words.add(trimmed);
                    }


                }

                // 构造每个任务的 config JSON
                Map<String, Object> configMap = new HashMap<>();
                configMap.put("batchId", batchId);
                configMap.put("isSystemImport", isSystemImport);

                configMap.put("generateWordImage", generateWordImage);
                configMap.put("generateShuffledVersion", generateShuffledVersion);
                configMap.put("dictName", dictName);
                configMap.put("domain", domain);
                configMap.put("description", description);
                configMap.put("targetDictGroupId", targetDictGroupId);
                configMap.put("targetDictGroupIds", targetDictGroupIds);
                configMap.put("targetGameHallIds", targetGameHallIds);

                configMap.put("words", words);

                ImportTask task = new ImportTask();
                User systemUser = new User();
                systemUser.setId(Constants.SYS_USER_SYS_ID);
                task.setOwner(systemUser);
                task.setConfig(JsonUtils.toJson(configMap));
                task.setStatus("PENDING");
                task.setFileName(fileName);
                task.setCreateTime(new Date());
                task.setUpdateTime(new Date());

                importTaskBo.createEntity(task);
                
                // 异步执行
                dictImportBo.executeImportTask(task.getId());
                createdCount++;
            }

            return Result.success("成功为 " + createdCount + " 本词书创建并拉起导入后台任务！批次号为: " + batchId);
        } catch (Exception e) {
            return Result.fail("批量导入初始化时发生异常: " + e.getMessage());
        }
    }

    @GetMapping("/allBatches")
    public Result<Map<String, List<Map<String, Object>>>> getAllBatches() {
        try {
            String sql = "SELECT * FROM import_task ORDER BY create_time DESC";
            List<Map<String, Object>> rows = jdbcTemplate.queryForList(sql);
            
            Map<String, List<Map<String, Object>>> batchMap = new LinkedHashMap<>();
            
            for (Map<String, Object> row : rows) {
                String config = (String) row.get("config");
                if (config == null || config.trim().isEmpty()) continue;
                
                try {
                    Map<String, Object> cfgMap = JsonUtils.parseMap(config);
                    String batchId = (String) cfgMap.get("batchId");
                    if (batchId == null || batchId.trim().isEmpty()) {
                        batchId = "UNBATCHED";
                    }
                    
                    Map<String, Object> taskInfo = new HashMap<>();
                    taskInfo.put("id", row.get("id"));
                    taskInfo.put("status", row.get("status"));
                    taskInfo.put("totalWords", row.get("total_words"));
                    taskInfo.put("processedWords", row.get("processed_words"));
                    taskInfo.put("fileName", row.get("file_name"));
                    taskInfo.put("dictName", cfgMap.get("dictName"));
                    taskInfo.put("dictId", cfgMap.get("dictId"));
                    taskInfo.put("createTime", row.get("create_time"));
                    taskInfo.put("log", row.get("log"));
                    taskInfo.put("isThreadRunning", beidanci.service.bo.DictImportBo.runningTaskIds.contains(row.get("id")));

                    batchMap.computeIfAbsent(batchId, k -> new ArrayList<>()).add(taskInfo);

                } catch (Exception ignore) {}
            }
            return Result.success(batchMap);
        } catch (Exception e) {
            return Result.fail("获取批次任务列表失败: " + e.getMessage());
        }
    }

    @PostMapping("/deleteBatch")
    public Result<String> deleteBatch(@RequestParam String batchId) {
        try {
            if ("UNBATCHED".equals(batchId)) {
                return Result.fail("不可删除未指定批次(UNBATCHED)的任务");
            }
            
            String sql = "SELECT id, config, status FROM import_task";
            List<Map<String, Object>> rows = jdbcTemplate.queryForList(sql);
            
            // 1. 安全前置校验：如果批次中仍有待执行或运行中任务，禁止物理删除
            for (Map<String, Object> row : rows) {
                String config = (String) row.get("config");
                if (config == null || config.trim().isEmpty()) continue;
                try {
                    Map<String, Object> cfgMap = JsonUtils.parseMap(config);
                    String bId = (String) cfgMap.get("batchId");
                    if (batchId.equals(bId)) {
                        String status = (String) row.get("status");
                        if ("PENDING".equals(status) || "RUNNING".equals(status)) {
                            return Result.fail("删除失败！该批次内尚有词书正在等待(PENDING)或执行(RUNNING)，请点击旁边的「中止」按钮叫停任务链后再操作。");
                        }
                    }
                } catch (Exception ignore) {}
            }

            
            int dictDeletedCount = 0;
            int taskDeletedCount = 0;
            
            for (Map<String, Object> row : rows) {
                String config = (String) row.get("config");
                if (config == null || config.trim().isEmpty()) continue;
                
                try {
                    Map<String, Object> cfgMap = JsonUtils.parseMap(config);
                    String bId = (String) cfgMap.get("batchId");
                    if (batchId.equals(bId)) {
                        String dictId = (String) cfgMap.get("dictId");
                        if (dictId != null && !dictId.trim().isEmpty()) {
                            dictBo.deleteSystemDictSafely(dictId);
                            dictDeletedCount++;
                        }

                        
                        jdbcTemplate.update("DELETE FROM import_task WHERE id = ?", row.get("id"));
                        taskDeletedCount++;
                    }
                } catch (Exception ignore) {}
            }
            
            return Result.success("成功删除批次 " + batchId + "：共清理词书 " + dictDeletedCount + " 本，任务记录 " + taskDeletedCount + " 条。");
        } catch (Exception e) {
            return Result.fail("删除批次失败: " + e.getMessage());
        }
    }

    @PostMapping("/cancelBatch")
    public Result<String> cancelBatch(@RequestParam String batchId) {
        try {
            if ("UNBATCHED".equals(batchId)) {
                return Result.fail("无法操作未指定批次(UNBATCHED)的任务");
            }
            
            String sql = "SELECT id, config FROM import_task WHERE status IN ('PENDING', 'RUNNING')";
            List<Map<String, Object>> rows = jdbcTemplate.queryForList(sql);
            
            int canceledCount = 0;
            
            for (Map<String, Object> row : rows) {
                String config = (String) row.get("config");
                if (config == null || config.trim().isEmpty()) continue;
                
                try {
                    Map<String, Object> cfgMap = JsonUtils.parseMap(config);
                    String bId = (String) cfgMap.get("batchId");
                    if (batchId.equals(bId)) {
                        jdbcTemplate.update("UPDATE import_task SET status = 'CANCELED' WHERE id = ?", row.get("id"));
                        beidanci.service.bo.DictImportBo.canceledTaskIds.add((String) row.get("id"));
                        canceledCount++;
                    }

                } catch (Exception ignore) {}
            }

            return Result.success("终止指令已成功下发，批次 " + batchId + " 内的 " + canceledCount + " 个任务正在平息退出。");


        } catch (Exception e) {
            return Result.fail("中止批次任务失败: " + e.getMessage());
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
