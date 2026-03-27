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

    @PostMapping("/admin/cigen/startBatchOptimize.do")
    public Result<String> startBatchOptimize(@RequestParam("userId") String userId) {
        synchronized (currentTask) {
            if (currentTask.isRunning) {
                return Result.fail("有一个词根优化任务正在运行中，请稍后再试");
            }
            User user = userBo.findById(userId);
            if (user == null || !user.getIsAdmin()) return Result.fail("无权限");

            currentTask.reset();
            currentTask.isRunning = true;

            new Thread(() -> {
                try {
                    logger.info("开始批量词根解析优化任务");
                    currentTask.statusMsg = "正在获取词根数据...";
                    List<CigenBo.CigenWordLinkDto> links = cigenBo.getAllCigenWordLinks();
                    currentTask.totalIndices = links.size();
                    currentTask.statusMsg = "正在优化中";

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
                            // 控制频率，防止 API 限流或数据库负载波动
                            Thread.sleep(500); 
                        } catch (Exception e) {
                            logger.error("词根优化异常: word=" + link.getSpell(), e);
                        }
                    }
                    if (currentTask.isRunning) currentTask.statusMsg = "任务完成";
                } catch (Exception e) {
                    logger.error("批量优化任务异常", e);
                    currentTask.statusMsg = "任务异常退出: " + e.getMessage();
                } finally {
                    currentTask.isRunning = false;
                }
            }).start();

            return Result.success("任务已启动");
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
