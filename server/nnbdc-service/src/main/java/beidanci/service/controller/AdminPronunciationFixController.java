package beidanci.service.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.WordBo;
import beidanci.service.po.User;
import beidanci.service.po.Word;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
public class AdminPronunciationFixController {
    private static final Logger logger = LoggerFactory.getLogger(AdminPronunciationFixController.class);

    @Autowired
    private WordBo wordBo;

    @Autowired
    private UserBo userBo;

    private static final PronunciationFixTask currentTask = new PronunciationFixTask();

    @PostMapping("/admin/pronunciation/startFix.do")
    public Result<String> startFix(@RequestParam("userId") String userId,
                                   @RequestParam(value = "fixUk", defaultValue = "true") boolean fixUk,
                                   @RequestParam(value = "fixUs", defaultValue = "true") boolean fixUs) {
        synchronized (currentTask) {
            if (currentTask.isRunning) {
                return Result.fail("有一个发音补齐任务正在运行中，请稍后再试");
            }
            User user = userBo.findById(userId);
            if (user == null || !user.getIsAdmin()) return Result.fail("无权限");

            currentTask.reset();
            currentTask.isRunning = true;
            currentTask.fixUk = fixUk;
            currentTask.fixUs = fixUs;

            new Thread(() -> {
                try {
                    List<Word> allWords = wordBo.getAllWords();
                    currentTask.totalIndices = allWords.size();
                    currentTask.statusMsg = "正在逐词补齐发音...";

                    for (int i = 0; i < allWords.size(); i++) {
                        if (!currentTask.isRunning) break;
                        Word w = allWords.get(i);
                        currentTask.currentIndex = i + 1;

                        try {
                            Map<String, Object> log = new HashMap<>();
                            log.put("spell", w.getSpell());
                            if (currentTask.fixUk) {
                                String ukPath = wordBo.downloadWordSound(w.getSpell(), "_uk");
                                log.put("uk", ukPath != null ? "OK" : "FAIL");
                            }
                            if (currentTask.fixUs) {
                                String usPath = wordBo.downloadWordSound(w.getSpell(), "_us");
                                log.put("us", usPath != null ? "OK" : "FAIL");
                            }
                            synchronized (currentTask) {
                                if ("FAIL".equals(log.get("uk"))) currentTask.ukFail++;
                                else if (currentTask.fixUk) currentTask.ukOk++;
                                if ("FAIL".equals(log.get("us"))) currentTask.usFail++;
                                else if (currentTask.fixUs) currentTask.usOk++;
                                if ("FAIL".equals(log.get("uk")) || "FAIL".equals(log.get("us"))) {
                                    if (currentTask.failedLogs.size() < 100) {
                                        currentTask.failedLogs.add(log);
                                    }
                                }
                            }
                        } catch (Exception e) {
                            logger.error("发音补齐异常: word=" + w.getSpell(), e);
                            Map<String, Object> log = new HashMap<>();
                            log.put("spell", w.getSpell());
                            log.put("error", e.getMessage());
                            synchronized (currentTask) {
                                if (currentTask.failedLogs.size() < 100) {
                                    currentTask.failedLogs.add(log);
                                }
                            }
                        }
                    }
                    currentTask.statusMsg = currentTask.isRunning ? "发音补齐任务完成" : "任务已中止";
                } catch (Exception e) {
                    logger.error("发音补齐任务异常", e);
                    currentTask.statusMsg = "任务异常退出: " + e.getMessage();
                } finally {
                    currentTask.isRunning = false;
                }
            }).start();

            return Result.success("发音补齐任务已启动");
        }
    }

    @GetMapping("/admin/pronunciation/fixStatus.do")
    public Result<PronunciationFixTask> getFixStatus() {
        return Result.success(currentTask);
    }

    @PostMapping("/admin/pronunciation/stopFix.do")
    public Result<String> stopFix(@RequestParam("userId") String userId) {
        User user = userBo.findById(userId);
        if (user == null || !user.getIsAdmin()) return Result.fail("无权限");
        currentTask.isRunning = false;
        currentTask.statusMsg = "已手动中止";
        return Result.success("已请求停止任务");
    }

    public static class PronunciationFixTask {
        public boolean isRunning = false;
        public boolean fixUk = true;
        public boolean fixUs = true;
        public int totalIndices = 0;
        public int currentIndex = 0;
        public int ukOk = 0;
        public int usOk = 0;
        public int ukFail = 0;
        public int usFail = 0;
        public String statusMsg = "等待中";
        public List<Map<String, Object>> failedLogs = new ArrayList<>();

        public void reset() {
            isRunning = false;
            fixUk = true;
            fixUs = true;
            totalIndices = 0;
            currentIndex = 0;
            ukOk = 0;
            usOk = 0;
            ukFail = 0;
            usFail = 0;
            statusMsg = "等待中";
            failedLogs.clear();
        }
    }
}