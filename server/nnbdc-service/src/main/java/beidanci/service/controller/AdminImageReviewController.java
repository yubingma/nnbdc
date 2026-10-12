package beidanci.service.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import beidanci.api.Result;
import beidanci.api.model.*;
import beidanci.service.bo.AiBo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.bo.WordImageBo;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.WordBo;
import beidanci.service.po.SysParam;
import beidanci.service.po.Word;
import beidanci.service.po.WordImage;
import beidanci.service.po.User;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.SysParamUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.apache.commons.lang3.StringUtils;
import java.io.File;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

@RestController
public class AdminImageReviewController {
    private static final Logger logger = LoggerFactory.getLogger(AdminImageReviewController.class);

    /** 批量审图的进度放在 sys_param 里：服务重启后能接着上次的位置继续审，不会再从头扫一遍 */
    private static final String PROGRESS_PARAM = "wordImageReviewProgress";

    /**
     * 并发送审的路数。
     *
     * 实测（2026-10-12，脚本 tmp/probe_sustained.py）：百炼 qwen3-vl-plus 用 16 路连续打满 30 秒、
     * 814 张零限流零失败，吞吐 26.5 张/秒，单张 p50 从串行时的 0.67 秒降到 0.49 秒；
     * 32 路也没触发限流。取 16 路是给挂在同一个 API Key 上的语音合成、AI 短文等调用留出余量。
     */
    private static final int REVIEW_CONCURRENCY = 16;

    /**
     * 一批最多送审多少张。批内并发跑完才把游标落一次库（游标取本批最后一张的 id），
     * 所以服务重启后最多重审这一批。批太大中断时要重审的张数多，太小则落库太频繁。
     */
    private static final int REVIEW_BATCH_SIZE = REVIEW_CONCURRENCY * 4;

    @Autowired
    private AiBo aiBo;

    @Autowired
    private WordImageBo wordImageBo;

    @Autowired
    private SysParamUtil sysParamUtil;

    @Autowired
    private UserBo userBo;

    @Autowired
    private WordBo wordBo;

    @Autowired
    private SysParamBo sysParamBo;

    @PostMapping("/admin/image/review.do")
    public Result<Map<String, String>> reviewImage(@RequestParam("imageId") String imageId) {
        try {
            WordImage image = wordImageBo.findById(imageId);
            if (image == null) return Result.fail("配图不存在");
            Word word = image.getWord();
            if (word == null) return Result.fail("单词不存在");
            String spell = word.getSpell();

            String absolutePath = new File(sysParamUtil.getImageBaseDir() + "/word", image.getImageFile()).getAbsolutePath();
            File imgFile = new File(absolutePath);
            if (!imgFile.exists()) return Result.fail("本地文件不存在");

            String aiResultStr = aiBo.reviewImage(spell, absolutePath);
            if (aiResultStr == null) return Result.fail("审图没拿到结论（AI 调用失败）");
            ObjectMapper mapper = new ObjectMapper();
            Map<String, String> res = mapper.readValue(aiResultStr, new com.fasterxml.jackson.core.type.TypeReference<Map<String, String>>(){});
            return Result.success(res);
        } catch(Exception e) {
            logger.error("审图接口异常", e);
            return Result.fail(e.getMessage());
        }
    }

    @GetMapping("/admin/image/getDictImages.do")
    public Result<List<Map<String, Object>>> getDictImages(@RequestParam("dictId") String dictId) {
        try {
            List<Map<String, Object>> result = new ArrayList<>();
            List<WordImageDto> images = wordBo.getWordImagesOfDict(dictId);
            for (WordImageDto imgDto : images) {
                Map<String, Object> map = new HashMap<>();
                map.put("imageId", imgDto.getId());
                map.put("imageFile", imgDto.getImageFile());
                map.put("wordId", imgDto.getWordId());
                map.put("status", imgDto.getStatus());
                Word w = wordBo.findById(imgDto.getWordId());
                if (w != null) {
                    map.put("spell", w.getSpell());
                } else {
                    map.put("spell", "未知");
                }
                result.add(map);
            }
            return Result.success(result);
        } catch(Exception e) {
            return Result.fail(e.getMessage());
        }
    }

    @PostMapping("/admin/image/delete.do")
    public Result<String> deleteImage(@RequestParam("imageId") String imageId, @RequestParam("userId") String userId) {
        try {
            User user = userBo.findById(userId);
            if (user == null || !user.getIsAdmin()) return Result.fail("无权限");
            Result<Object> res = wordImageBo.deleteWordImage(imageId, user, true);
            if(res.isSuccess()) {
                return Result.success("删除成功");
            } else {
                return Result.fail(res.getMsg());
            }
        } catch(Exception e) {
            return Result.fail(e.getMessage());
        }
    }

    /** 批量审图的实时状态。只在内存里；"上次审到哪"的进度落在 sys_param 里，重启不丢 */
    private final AdminImageReviewTask currentTask = new AdminImageReviewTask();

    /**
     * 启动（或继续）批量审图。
     *
     * 审图期间 AI 判删的图**当场就删**：以前是攒一个"待删清单"放在内存里，等服务重启后
     * 清单就没了，「批量删除」按钮再也点不出那批图 —— 管理员以为清过了，其实一张没删。
     * 进度（审到哪个 id）落在 sys_param 里，服务重启或手动停止后，再点一次按钮从这里接着审。
     */
    @PostMapping("/admin/image/startBatchReview.do")
    public Result<String> startBatchReview(@RequestParam(value = "dictId", defaultValue = "0") String dictId,
                                           @RequestParam("userId") String userId) {
        synchronized (currentTask) {
            if (currentTask.isRunning) {
                return Result.fail("有一个审核任务正在运行中，请稍后再试");
            }
            User user = userBo.findById(userId);
            if (user == null || !user.getIsAdmin()) return Result.fail("无权限");

            ReviewProgress saved = loadProgress();
            // 换了词书就不能拿别的词书的游标往后跳，从头审这本
            boolean resume = saved != null && dictId.equals(saved.dictId) && saved.imageIdCursor != null;

            currentTask.reset();
            currentTask.dictId = dictId;
            currentTask.isRunning = true;
            currentTask.statusMsg = resume ? "准备从上次中断处继续" : "准备从头开始";

            new Thread(() -> runBatchReview(dictId, resume ? saved : null)).start();

            return Result.success(resume ? "任务已启动：从上次中断处继续" : "任务已启动：从头开始扫描");
        }
    }

    /**
     * 全库扫一遍配图，AI 判删就当场删、判过就置为已通过；没结论的图保持审核中，等定时重审。
     *
     * 送审是多路并发的（见 {@link #REVIEW_CONCURRENCY}）。以前是一张一张串行、每张之间还空等
     * 800 毫秒，3 万多张要跑将近 18 个小时，而其中四成时间纯粹是睡掉的。
     *
     * @param resume 上次的进度（为空表示这一轮从头开始）
     */
    private void runBatchReview(String dictId, ReviewProgress resume) {
        String cursor = resume == null ? null : resume.imageIdCursor;
        int reviewed = resume == null ? 0 : resume.reviewedCount;
        int deleted = resume == null ? 0 : resume.deletedCount;
        int undecided = resume == null ? 0 : resume.undecidedCount;
        int approvedThisRun = 0;
        AtomicInteger handled = new AtomicInteger();
        ExecutorService pool = Executors.newFixedThreadPool(REVIEW_CONCURRENCY);
        try {
            List<WordImageDto> images = new ArrayList<>(wordBo.getWordImagesOfDict(dictId));
            // 按 id 排序，游标才有确定的先后顺序
            images.sort((a, b) -> a.getId().compareTo(b.getId()));
            if (cursor != null) {
                final String from = cursor;
                images.removeIf(image -> image.getId().compareTo(from) <= 0);
            }
            currentTask.totalImages = images.size();
            currentTask.statusMsg = cursor == null ? "正在从头扫描" : "正在从上次中断处继续扫描";
            logger.info("开始批量审图: dictId={}, 待审 {} 张, 起点={}, 并发={}", dictId, images.size(), cursor,
                    REVIEW_CONCURRENCY);

            for (int from = 0; from < images.size() && currentTask.isRunning; from += REVIEW_BATCH_SIZE) {
                List<WordImageDto> batch = images.subList(from, Math.min(from + REVIEW_BATCH_SIZE, images.size()));
                List<Callable<Map<String, Object>>> tasks = new ArrayList<>(batch.size());
                for (WordImageDto image : batch) {
                    tasks.add(() -> {
                        try {
                            return reviewOneImage(image);
                        } finally {
                            currentTask.currentIndex = handled.incrementAndGet();
                        }
                    });
                }

                // invokeAll 阻塞到本批全部审完，结果顺序与 batch 一一对应；
                // 计数与游标都在本线程推进，不给并发留竞态
                List<Future<Map<String, Object>>> futures = pool.invokeAll(tasks);
                for (int i = 0; i < batch.size(); i++) {
                    WordImageDto image = batch.get(i);
                    Map<String, Object> verdict = null;
                    try {
                        verdict = futures.get(i).get();
                    } catch (Exception e) {
                        logger.error("审图异常, imgId=" + image.getId(), e);
                    }

                    if (verdict == null) {
                        undecided++;
                    } else if ("DELETE".equals(String.valueOf(verdict.get("action")))) {
                        deleted++;
                        Word word = wordBo.findById(image.getWordId());
                        currentTask.deletedImages
                                .add(buildDeletedInfo(image, word == null ? null : word.getSpell(), verdict));
                    } else {
                        approvedThisRun++;
                    }
                    reviewed++;
                }

                cursor = batch.get(batch.size() - 1).getId();
                saveProgressQuietly(dictId, cursor, reviewed, deleted, undecided);
            }

            if (currentTask.isRunning) {
                // 扫到结尾：这一轮完成，清掉游标，下次点按钮从头开新一轮
                saveProgressQuietly(dictId, null, reviewed, deleted, undecided);
                currentTask.statusMsg = String.format("本轮审完：共审 %d 张，删除 %d 张，通过 %d 张，无结论 %d 张",
                        reviewed, deleted, approvedThisRun, undecided);
            } else {
                saveProgressQuietly(dictId, cursor, reviewed, deleted, undecided);
                currentTask.statusMsg = String.format("已手动停止：共审 %d 张，删除 %d 张，下次从这里继续", reviewed, deleted);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            saveProgressQuietly(dictId, cursor, reviewed, deleted, undecided);
            currentTask.statusMsg = String.format("任务被中断：共审 %d 张，删除 %d 张，下次从这里继续", reviewed, deleted);
        } catch (Exception e) {
            saveProgressQuietly(dictId, cursor, reviewed, deleted, undecided);
            logger.error("批量扫描异常", e);
            currentTask.statusMsg = "任务异常退出: " + e.getMessage();
        } finally {
            pool.shutdown();
            currentTask.isRunning = false;
        }
    }

    /** 送一张配图给 AI 审，并按结论落库：判删当场删、判过置为已通过、没结论就留在审核中等重审 */
    private Map<String, Object> reviewOneImage(WordImageDto image) throws IllegalAccessException {
        Word word = wordBo.findById(image.getWordId());
        return wordImageBo.reviewImageAndApply(image.getId(), word == null ? null : word.getSpell(),
                image.getImageFile());
    }

    private Map<String, Object> buildDeletedInfo(WordImageDto image, String spell, Map<String, Object> verdict) {
        Map<String, Object> info = new HashMap<>();
        info.put("imageId", image.getId());
        info.put("imageFile", image.getImageFile());
        info.put("spell", spell);
        info.put("reason", verdict.get("reason"));
        return info;
    }

    @GetMapping("/admin/image/batchReviewStatus.do")
    public Result<AdminImageReviewTask> getBatchReviewStatus() {
        if (!currentTask.isRunning) {
            ReviewProgress saved = loadProgress();
            currentTask.savedProgress = saved == null ? null : saved.describe();
        }
        return Result.success(currentTask);
    }

    @PostMapping("/admin/image/stopBatchReview.do")
    public Result<String> stopBatchReview(@RequestParam("userId") String userId) {
        User user = userBo.findById(userId);
        if (user == null || !user.getIsAdmin()) return Result.fail("无权限");
        currentTask.isRunning = false;
        currentTask.statusMsg = "已手动中止";
        return Result.success("已请求停止任务");
    }

    /**
     * 旧的「批量删除标记图」入口。现在审图判定为删就当场删，不再有"标记待删"这一步，
     * 老版本管理台还会调到这里，直接返回 0 让它自然结束。
     */
    @PostMapping("/admin/image/deleteMarked.do")
    public Result<Integer> deleteMarkedImages(@RequestParam("userId") String userId) {
        return Result.success(0);
    }

    private ReviewProgress loadProgress() {
        try {
            SysParam param = sysParamBo.findById(PROGRESS_PARAM);
            if (param == null || StringUtils.isBlank(param.getParamValue())) return null;
            return JsonUtils.makeObject(param.getParamValue(), ReviewProgress.class);
        } catch (Exception e) {
            logger.error("解析审图进度失败", e);
            return null;
        }
    }

    private void saveProgressQuietly(String dictId, String cursor, int reviewed, int deleted, int undecided) {
        try {
            ReviewProgress progress = new ReviewProgress();
            progress.dictId = dictId;
            progress.imageIdCursor = cursor;
            progress.reviewedCount = reviewed;
            progress.deletedCount = deleted;
            progress.undecidedCount = undecided;
            progress.updatedAt = new SimpleDateFormat("yyyy-MM-dd HH:mm").format(new Date());

            String json = JsonUtils.toJson(progress);
            SysParam param = sysParamBo.findById(PROGRESS_PARAM);
            if (param == null) {
                sysParamBo.createEntity(new SysParam(PROGRESS_PARAM, json, "AI 配图批量审核进度（游标），服务重启后可接着审"));
            } else {
                param.setParamValue(json);
                sysParamBo.updateEntity(param);
            }
        } catch (Exception e) {
            logger.error("保存审图进度失败: dictId={}, cursor={}", dictId, cursor, e);
        }
    }

    /** 批量审图的进度快照（以 JSON 存在 sys_param 里） */
    public static class ReviewProgress {
        public String dictId;
        /** 已经审到的最后一张图的 id；为空表示这一轮已审完 */
        public String imageIdCursor;
        public int reviewedCount;
        public int deletedCount;
        public int undecidedCount;
        public String updatedAt;

        public String describe() {
            if (imageIdCursor == null) {
                return String.format("上一轮已审完：共审 %d 张，删除 %d 张，无结论 %d 张（%s）；再点按钮从头审新一轮",
                        reviewedCount, deletedCount, undecidedCount, updatedAt);
            }
            return String.format("上次审到 %s：已审 %d 张，删除 %d 张，无结论 %d 张（%s）；再点按钮从这里继续",
                    imageIdCursor, reviewedCount, deletedCount, undecidedCount, updatedAt);
        }
    }

    public static class AdminImageReviewTask {
        public boolean isRunning = false;
        public int totalImages = 0;
        public int currentIndex = 0;
        public String statusMsg = "等待中";
        public String dictId;
        /** 本次已删除的配图（含 AI 给的理由）；只在内存里，服务重启后清空，逐条删除记录在服务端日志里可查 */
        public List<Map<String, Object>> deletedImages = new ArrayList<>();
        /** 落库的上次进度摘要，不在跑的时候给页面看 */
        public String savedProgress;

        public void reset() {
            isRunning = false;
            totalImages = 0;
            currentIndex = 0;
            statusMsg = "等待中";
            dictId = null;
            deletedImages.clear();
            savedProgress = null;
        }
    }
}
