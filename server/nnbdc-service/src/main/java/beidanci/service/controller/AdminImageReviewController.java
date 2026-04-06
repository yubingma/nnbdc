package beidanci.service.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import beidanci.api.Result;
import beidanci.api.model.*;
import beidanci.service.bo.AiBo;
import beidanci.service.bo.WordImageBo;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.WordBo;
import beidanci.service.util.SysParamUtil;
import beidanci.service.po.WordImage;
import beidanci.service.po.Word;
import beidanci.service.po.User;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.io.File;
import java.util.*;

@RestController
public class AdminImageReviewController {
    private static final Logger logger = LoggerFactory.getLogger(AdminImageReviewController.class);

    @Autowired
    private AiBo aiBo;

    @Autowired
    private WordImageBo wordImageBo;

    @Autowired
    private SysParamUtil sysParamUtil;
    
    @Autowired
    private UserBo userBo;

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
            ObjectMapper mapper = new ObjectMapper();
            Map<String, String> res = mapper.readValue(aiResultStr, new com.fasterxml.jackson.core.type.TypeReference<Map<String, String>>(){});
            return Result.success(res);
        } catch(Exception e) {
            logger.error("审图接口异常", e);
            return Result.fail(e.getMessage());
        }
    }
    
    @Autowired
    private WordBo wordBo;

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
    
    private AdminImageReviewTask currentTask = new AdminImageReviewTask();

    @PostMapping("/admin/image/startBatchReview.do")
    public Result<String> startBatchReview(@RequestParam(value="dictId", defaultValue="0") String dictId, 
                                           @RequestParam(value="autoDelete", defaultValue="false") boolean autoDelete,
                                           @RequestParam("userId") String userId) {
        synchronized(currentTask) {
            if (currentTask.isRunning) {
                return Result.fail("有一个审核任务正在运行中，请稍后再试");
            }
            User user = userBo.findById(userId);
            if (user == null || !user.getIsAdmin()) return Result.fail("无权限");

            currentTask.reset();
            currentTask.autoDelete = autoDelete;
            currentTask.dictId = dictId;
            currentTask.isRunning = true;
            
            new Thread(() -> {
                try {
                    logger.info("开始批量图片审核任务: dictId=" + dictId + ", autoDelete=" + autoDelete);
                    currentTask.statusMsg = "正在获取图片...";
                    List<WordImageDto> images = wordBo.getWordImagesOfDict(dictId);
                    currentTask.totalImages = images.size();
                    currentTask.statusMsg = "正在扫描中";
                    
                    for (int i = 0; i < images.size(); i++) {
                        if (!currentTask.isRunning) break;
                        WordImageDto imgDto = images.get(i);
                        currentTask.currentIndex = i + 1;
                        
                        try {
                            WordImage img = wordImageBo.findById(imgDto.getId());
                            if (img != null && imgDto.getWordId() != null) {
                                Word w = wordBo.findById(imgDto.getWordId());
                                String spell = w != null ? w.getSpell() : null;
                                String absPath = new File(sysParamUtil.getImageBaseDir() + "/word", img.getImageFile()).getAbsolutePath();
                                File imgFile = new File(absPath);
                                if (imgFile.exists() && spell != null) {
                                    String aiResultStr = aiBo.reviewImage(spell, absPath);
                                    ObjectMapper mapper = new ObjectMapper();
                                    Map<String, String> res = mapper.readValue(aiResultStr, new com.fasterxml.jackson.core.type.TypeReference<Map<String, String>>(){});
                                    if ("DELETE".equals(res.get("action"))) {
                                        Map<String, Object> markedInfo = new HashMap<>();
                                        markedInfo.put("imageId", img.getId());
                                        markedInfo.put("imageFile", img.getImageFile());
                                        markedInfo.put("spell", spell);
                                        markedInfo.put("reason", res.get("reason"));
                                        
                                        if (autoDelete) {
                                            wordImageBo.deleteWordImage(img.getId(), user, true);
                                            synchronized(currentTask) { currentTask.deletedImages.add(markedInfo); }
                                        } else {
                                            synchronized(currentTask) { currentTask.markedImages.add(markedInfo); }
                                        }
                                    }
                                }
                            }
                            Thread.sleep(800); 
                        } catch(Exception e) {
                            logger.error("审图异常, imgId=" + imgDto.getId(), e);
                        }
                    }
                    if (currentTask.isRunning) currentTask.statusMsg = "任务完成";
                } catch(Exception e) {
                    logger.error("批量扫描异常", e); 
                    currentTask.statusMsg = "任务异常退出: " + e.getMessage();
                } finally {
                    currentTask.isRunning = false;
                }
            }).start();
            
            return Result.success("任务已启动");
        }
    }

    @GetMapping("/admin/image/batchReviewStatus.do")
    public Result<AdminImageReviewTask> getBatchReviewStatus() {
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

    @PostMapping("/admin/image/deleteMarked.do")
    public Result<Integer> deleteMarkedImages(@RequestParam("userId") String userId) {
        User user = userBo.findById(userId);
        if (user == null || !user.getIsAdmin()) return Result.fail("无权限");
        
        int deleteCount = 0;
        synchronized(currentTask) {
            Iterator<Map<String, Object>> it = currentTask.markedImages.iterator();
            while(it.hasNext()) {
                Map<String, Object> info = it.next();
                try {
                    String imageId = (String) info.get("imageId");
                    Result<Object> delRes = wordImageBo.deleteWordImage(imageId, user, true);
                    if (delRes.isSuccess()) {
                        info.put("reason", info.get("reason") + " (已应用删除)");
                        currentTask.deletedImages.add(info);
                        it.remove();
                        deleteCount++;
                    }
                } catch(Exception e) {
                    logger.error("删除标记的图片失败", e);
                }
            }
        }
        return Result.success(deleteCount);
    }

    public static class AdminImageReviewTask {
        public boolean isRunning = false;
        public int totalImages = 0;
        public int currentIndex = 0;
        public String statusMsg = "等待中";
        public String dictId;
        public boolean autoDelete;
        public List<Map<String, Object>> markedImages = new ArrayList<>();
        public List<Map<String, Object>> deletedImages = new ArrayList<>();

        public void reset() {
            isRunning = false;
            totalImages = 0;
            currentIndex = 0;
            statusMsg = "等待中";
            markedImages.clear();
            deletedImages.clear();
        }
    }
}
