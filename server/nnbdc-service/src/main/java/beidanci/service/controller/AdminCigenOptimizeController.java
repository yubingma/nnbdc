package beidanci.service.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.service.bo.AiBo;
import beidanci.service.bo.CigenBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.User;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
public class AdminCigenOptimizeController {
    private static final Logger logger = LoggerFactory.getLogger(AdminCigenOptimizeController.class);

    @Autowired
    private AiBo aiBo;

    @Autowired
    private CigenBo cigenBo;

    @Autowired
    private UserBo userBo;

    private static final CigenOptimizeTask currentTask = new CigenOptimizeTask();

    @PostMapping("/admin/cigen/startFullOptimize.do")
    public Result<String> startFullOptimize(@RequestParam("userId") String userId) {
        synchronized (currentTask) {
            if (currentTask.isRunning) {
                return Result.fail("有一个词库优化任务正在运行中，请稍后再试");
            }
            User user = userBo.findById(userId);
            if (user == null || !user.getIsAdmin()) return Result.fail("无权限");

            currentTask.reset();
            currentTask.isRunning = true;

            new Thread(() -> {
                try {
                    // 第一阶段：词库结构化 (Cigen 属性解析)
                    logger.info("开始词根结构化阶段");
                    currentTask.statusMsg = "正在获取词根数据进行结构化...";
                    List<Map<String, Object>> cigens = cigenBo.getAllCigens();
                    currentTask.totalIndices = cigens.size();
                    
                    for (int i = 0; i < cigens.size(); i++) {
                        if (!currentTask.isRunning) break;
                        Map<String, Object> cigen = cigens.get(i);
                        currentTask.currentIndex = i + 1;
                        String id = (String) cigen.get("id");
                        String description = (String) cigen.get("description");

                        // 跳过已结构化的
                        if (cigen.get("spell") != null && !cigen.get("spell").toString().isEmpty()) continue;

                        try {
                            String json = aiBo.parseCigenDescription(description);
                            if (json != null) {
                                Map<String, Object> data = beidanci.service.util.JsonUtils.parseMap(json);
                                String spell = (String) data.get("spell");
                                String category = (String) data.get("category");
                                String meaningCn = (String) data.get("meaningCn");
                                String meaningEn = (String) data.get("meaningEn");
                                if (spell != null && category != null) {
                                    cigenBo.updateCigenStructuredInfo(id, spell, category, meaningCn, meaningEn);
                                    
                                    // 添加日志用于前端展示
                                    Map<String, Object> log = new HashMap<>();
                                    log.put("spell", spell);
                                    log.put("before", description);
                                    log.put("after", String.format("[%s] %s: %s (%s)", category, spell, meaningCn, meaningEn));
                                    log.put("type", "STRUCTURED"); // 标记日志类型
                                    synchronized (currentTask) {
                                        currentTask.optimizedLogs.add(log);
                                    }
                                }
                            }
                            Thread.sleep(300);
                        } catch (Exception e) {
                            logger.error("词根结构化异常: id=" + id, e);
                        }
                    }

                    // 第二阶段：词根解析优化 (CigenWordLink 文本优化)
                    if (currentTask.isRunning) {
                        logger.info("开始词根解析优化阶段");
                        currentTask.statusMsg = "正在获取词根关系数据进行解析优化...";
                        List<CigenBo.CigenWordLinkDto> links = cigenBo.getAllCigenWordLinks();
                        currentTask.totalIndices = links.size();
                        currentTask.currentIndex = 0;

                        for (int i = 0; i < links.size(); i++) {
                            if (!currentTask.isRunning) break;
                            CigenBo.CigenWordLinkDto link = links.get(i);
                            currentTask.currentIndex = i + 1;

                            try {
                                String original = link.getTheExplain();
                                String optimized = aiBo.optimizeCigenExplain(link.getSpell(), original, link.getCigenDescription());
                                
                                if (optimized != null && !optimized.trim().equals(original.trim())) {
                                    cigenBo.updateExplain(link.getCigenId(), link.getWordId(), optimized);
                                    Map<String, Object> log = new HashMap<>();
                                    log.put("spell", link.getSpell());
                                    log.put("before", original);
                                    log.put("after", optimized);
                                    synchronized (currentTask) {
                                        currentTask.optimizedLogs.add(log);
                                    }
                                }
                                Thread.sleep(500); 
                            } catch (Exception e) {
                                logger.error("词根解析优化异常: word=" + link.getSpell(), e);
                            }
                        }
                    }
                    
                    if (currentTask.isRunning) currentTask.statusMsg = "全量优化任务完成";
                } catch (Exception e) {
                    logger.error("全量优化任务异常", e);
                    currentTask.statusMsg = "任务异常退出: " + e.getMessage();
                } finally {
                    currentTask.isRunning = false;
                }
            }).start();

            return Result.success("全量优化任务已启动");
        }
    }

    @GetMapping("/admin/cigen/batchOptimizeStatus.do")
    public Result<CigenOptimizeTask> getBatchOptimizeStatus() {
        return Result.success(currentTask);
    }

    @PostMapping("/admin/cigen/stopBatchOptimize.do")
    public Result<String> stopBatchOptimize(@RequestParam("userId") String userId) {
        User user = userBo.findById(userId);
        if (user == null || !user.getIsAdmin()) return Result.fail("无权限");
        currentTask.isRunning = false;
        currentTask.statusMsg = "已手动中止";
        return Result.success("已请求停止任务");
    }

    public static class CigenOptimizeTask {
        public boolean isRunning = false;
        public int totalIndices = 0;
        public int currentIndex = 0;
        public String statusMsg = "等待中";
        public List<Map<String, Object>> optimizedLogs = new ArrayList<>();

        public void reset() {
            isRunning = false;
            totalIndices = 0;
            currentIndex = 0;
            statusMsg = "等待中";
            optimizedLogs.clear();
        }
    }
}
