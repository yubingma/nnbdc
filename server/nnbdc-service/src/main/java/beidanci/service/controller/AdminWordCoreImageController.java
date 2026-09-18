package beidanci.service.controller;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

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
import beidanci.service.bo.WordCoreImageBo;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.po.WordCoreImage;

@RestController
public class AdminWordCoreImageController {

    private static final Logger logger = LoggerFactory.getLogger(AdminWordCoreImageController.class);

    @Autowired
    private WordCoreImageBo wordCoreImageBo;

    @Autowired
    private WordBo wordBo;

    @Autowired
    private UserBo userBo;

    private static final WordCoreImageBatchTask currentTask = new WordCoreImageBatchTask();

    @PostMapping("/admin/wordCoreImage/startBatch.do")
    public Result<String> startBatch(@RequestParam("userId") String userId) {
        synchronized (currentTask) {
            if (currentTask.isRunning) {
                return Result.fail("批量提取与生图任务已在运行中");
            }
            User user = userBo.findById(userId);
            if (user == null || !user.getIsAdmin()) {
                return Result.fail("无权限");
            }

            currentTask.reset();
            currentTask.isRunning = true;
            currentTask.totalWords = wordCoreImageBo.countTotalWords();
            currentTask.processedWords = wordCoreImageBo.countProcessedWords();
            currentTask.applicableCount = wordCoreImageBo.countApplicableWords();
            currentTask.skippedCount = wordCoreImageBo.countSkippedWords();
            currentTask.statusMsg = "任务启动中，正在扫描词库...";

            new Thread(() -> {
                try {
                    logger.info("启动一词多义核心意象批处理任务，词库总词数: {}, 已处理: {}",
                            currentTask.totalWords, currentTask.processedWords);

                    while (currentTask.isRunning) {
                        // 分批加载未处理的单词（按热门度降序排列）
                        List<Word> batch = wordCoreImageBo.findNextUnprocessedWords(20);
                        if (batch == null || batch.isEmpty()) {
                            currentTask.statusMsg = "全部词汇已处理完毕";
                            break;
                        }

                        for (Word word : batch) {
                            if (!currentTask.isRunning) {
                                break;
                            }

                            currentTask.currentWord = word.getSpell();
                            currentTask.statusMsg = String.format("正在处理: %s (已完成 %d / %d)",
                                    word.getSpell(), currentTask.processedWords, currentTask.totalWords);

                            try {
                                WordCoreImage wci = wordCoreImageBo.processWord(word);
                                currentTask.processedWords++;

                                Map<String, Object> logEntry = new HashMap<>();
                                logEntry.put("word", word.getSpell());
                                logEntry.put("time", System.currentTimeMillis());

                                if (Boolean.TRUE.equals(wci.getIsApplicable())) {
                                    currentTask.applicableCount++;
                                    logEntry.put("type", "APPLICABLE");
                                    logEntry.put("coreImage", wci.getCoreImage());
                                    logEntry.put("imageUrl", wci.getImageUrl());
                                    logEntry.put("imageStatus", wci.getImageStatus());
                                } else {
                                    currentTask.skippedCount++;
                                    logEntry.put("type", "SKIPPED");
                                    logEntry.put("reason", wci.getNotApplicableReason());
                                }

                                synchronized (currentTask) {
                                    currentTask.recentLogs.add(0, logEntry);
                                    if (currentTask.recentLogs.size() > 50) {
                                        currentTask.recentLogs.remove(currentTask.recentLogs.size() - 1);
                                    }
                                }

                                // 适当休眠，平滑调用频率
                                Thread.sleep(300);
                            } catch (Exception e) {
                                currentTask.failedCount++;
                                logger.error("处理单词异常: " + word.getSpell(), e);
                            }
                        }
                    }

                    if (currentTask.isRunning) {
                        currentTask.statusMsg = "批量处理任务已圆满完成";
                    }
                } catch (Exception e) {
                    logger.error("批量处理任务异常退出", e);
                    currentTask.statusMsg = "任务异常退出: " + e.getMessage();
                } finally {
                    currentTask.isRunning = false;
                    currentTask.currentWord = "";
                }
            }, "WordCoreImageBatchWorker").start();

            return Result.success("批量任务已成功在后台启动");
        }
    }

    @GetMapping("/admin/wordCoreImage/status.do")
    public Result<WordCoreImageBatchTask> getStatus() {
        synchronized (currentTask) {
            // 如果任务未在运行，刷新一次数据库最新统计
            if (!currentTask.isRunning) {
                currentTask.totalWords = wordCoreImageBo.countTotalWords();
                currentTask.processedWords = wordCoreImageBo.countProcessedWords();
                currentTask.applicableCount = wordCoreImageBo.countApplicableWords();
                currentTask.skippedCount = wordCoreImageBo.countSkippedWords();
                if (currentTask.recentLogs.isEmpty()) {
                    List<Map<String, Object>> recents = wordCoreImageBo.getRecentSuccessRecords(20);
                    for (Map<String, Object> r : recents) {
                        Map<String, Object> logEntry = new HashMap<>();
                        logEntry.put("word", r.get("word"));
                        logEntry.put("coreImage", r.get("core_image"));
                        logEntry.put("imageUrl", r.get("image_url"));
                        logEntry.put("imageStatus", r.get("image_status"));
                        logEntry.put("type", Boolean.TRUE.equals(r.get("is_applicable")) ? "APPLICABLE" : "SKIPPED");
                        logEntry.put("reason", r.get("not_applicable_reason"));
                        currentTask.recentLogs.add(logEntry);
                    }
                }
            }
            return Result.success(currentTask);
        }
    }

    @PostMapping("/admin/wordCoreImage/stopBatch.do")
    public Result<String> stopBatch(@RequestParam("userId") String userId) {
        User user = userBo.findById(userId);
        if (user == null || !user.getIsAdmin()) {
            return Result.fail("无权限");
        }
        currentTask.isRunning = false;
        currentTask.statusMsg = "管理员已手动请求中止";
        return Result.success("中止指令已发送");
    }

    @PostMapping("/admin/wordCoreImage/processSingle.do")
    public Result<WordCoreImage> processSingle(@RequestParam("spell") String spell, @RequestParam("userId") String userId) {
        User user = userBo.findById(userId);
        if (user == null || !user.getIsAdmin()) {
            return Result.fail("无权限");
        }

        Word word = wordBo.getWordBySpell(spell);
        if (word == null) {
            return Result.fail("单词不存在: " + spell);
        }

        WordCoreImage wci = wordCoreImageBo.processWord(word);
        return Result.success(wci);
    }

    public static class WordCoreImageBatchTask {
        public volatile boolean isRunning = false;
        public int totalWords = 0;
        public int processedWords = 0;
        public int applicableCount = 0;
        public int skippedCount = 0;
        public int failedCount = 0;
        public String currentWord = "";
        public String statusMsg = "任务空闲中";
        public List<Map<String, Object>> recentLogs = new ArrayList<>();

        public void reset() {
            failedCount = 0;
            currentWord = "";
            statusMsg = "准备中...";
            recentLogs.clear();
        }
    }
}
