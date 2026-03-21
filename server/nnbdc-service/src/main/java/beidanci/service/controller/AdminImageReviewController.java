package beidanci.service.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import beidanci.api.Result;
import beidanci.service.bo.AiBo;
import beidanci.service.bo.WordImageBo;
import beidanci.service.bo.UserBo;
import beidanci.service.util.SysParamUtil;
import beidanci.service.po.WordImage;
import beidanci.service.po.Word;
import beidanci.service.po.User;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.io.File;
import java.util.Map;

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
    private beidanci.service.bo.WordBo wordBo;

    @org.springframework.web.bind.annotation.GetMapping("/admin/image/getDictImages.do")
    public Result<java.util.List<Map<String, Object>>> getDictImages(@RequestParam("dictId") String dictId) {
        try {
            java.util.List<Map<String, Object>> result = new java.util.ArrayList<>();
            java.util.List<beidanci.api.model.WordImageDto> images = wordBo.getWordImagesOfDict(dictId);
            for (beidanci.api.model.WordImageDto imgDto : images) {
                Map<String, Object> map = new java.util.HashMap<>();
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
}
