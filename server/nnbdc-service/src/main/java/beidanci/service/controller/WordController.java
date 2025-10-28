package beidanci.service.controller;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.xml.bind.DatatypeConverter;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.WordImageDto;
import beidanci.service.bo.DictBo;
import beidanci.service.bo.DictWordBo;
import beidanci.service.bo.ErrorReportBo;
import beidanci.service.bo.InfoVoteLogBo;
import beidanci.service.bo.LearningDictBo;
import beidanci.service.bo.LearningWordBo;
import beidanci.service.bo.MasteredWordBo;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.UserStudyStepBo;
import beidanci.service.bo.WordAdditionalInfoBo;
import beidanci.service.bo.WordBo;
import beidanci.service.bo.WordImageBo;
import beidanci.service.bo.WordShortDescChineseBO;
import beidanci.service.bo.WrongWordBo;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.po.WordImage;
import beidanci.service.store.WordCache;
import beidanci.service.util.MyImage;
import beidanci.service.util.SysParamUtil;

@RestController
public class WordController {


    @Autowired
    WordCache wordCache;

    @Autowired
    WordBo wordBo;

    @Autowired
    WordShortDescChineseBO wordShortDescChineseBO;

    @Autowired
    WordAdditionalInfoBo wordAdditionalInfoBo;

    @Autowired
    LearningWordBo learningWordBo;

    @Autowired
    WrongWordBo wrongWordBo;

    @Autowired
    InfoVoteLogBo infoVoteLogBo;

    @Autowired
    ErrorReportBo errorReportBo;

    @Autowired
    DictBo dictBo;

    @Autowired
    SysParamUtil sysParamUtil;

    @Autowired
    WordImageBo wordImageBo;

    @Autowired
    DictWordBo dictWordBo;

    @Autowired
    UserBo userBo;

    @Autowired
    UserStudyStepBo userStudyStepBo;

    @Autowired
    LearningDictBo selectedDictBo;

    @Autowired
    MasteredWordBo masteredWordBo;


    @PutMapping("/handImage.do")
    @PreAuthorize("hasAnyRole('USER','ADMIN')")
    public Result<Integer> handImage(HttpServletRequest request, HttpServletResponse response, String id, String userId)
            throws IllegalArgumentException, IllegalAccessException, IOException {
        User user = userBo.findById(userId);
        Result<Integer> result = wordImageBo.handImage(id, user);
        return result;
    }

    @PutMapping("/footImage.do")
    @PreAuthorize("hasAnyRole('USER','ADMIN')")
    public Result<Integer> footImage(HttpServletRequest request, HttpServletResponse response, String id, String userId)
            throws IllegalArgumentException, IllegalAccessException, IOException {
        User user = userBo.findById(userId);
        Result<Integer> result = wordImageBo.footImage(id, user);
        return result;
    }

    @DeleteMapping("/deleteImage.do")
    @PreAuthorize("hasAnyRole('USER','ADMIN')")
    public Result<Object> deleteImage(HttpServletRequest request, HttpServletResponse response, String id, String userId)
            throws IllegalArgumentException, IllegalAccessException, IOException {
        User user = userBo.findById(userId);
        Result<Object> result = wordImageBo.deleteWordImage(id, user, true);
        return result;
    }

    @PostMapping(value = "/uploadWordImg.do")
    public Result<WordImageDto> uploadWordImg2(String wordId, String imgBase64String, String userId) throws Exception {
        User user = userBo.findById(userId);
        if (user == null) {
            return Result.fail("用户未登录");
        }

        // 图片文件上传
        String fileName;
        File targetFile;

        // 根据真实格式命名
        String baseName = wordId + "_" + System.currentTimeMillis();
        File tempTargetFile = new File(sysParamUtil.getImageBaseDir() + "/tmp/tmp_" + baseName);

        byte[] data = DatatypeConverter.parseBase64Binary(imgBase64String);
        try (OutputStream outputStream = new BufferedOutputStream(new FileOutputStream(tempTargetFile))) {
            outputStream.write(data);
        }
        // 探测真实格式并决定目标文件名
        String fmt = null;
        try {
            fmt = MyImage.getImageFormat(tempTargetFile);
            if (fmt == null) {
                fmt = MyImage.detectFormat(tempTargetFile);
            }
        } catch (IOException ignore) { }
        String ext = MyImage.normalizeExtByFormat(fmt);
        fileName = baseName + "." + ext;
        targetFile = new File(sysParamUtil.getImageBaseDir() + "/word/" + fileName);

        // 通过图像缩放生成大图（若可识别且可写则按原格式缩放；否则直接复制）
        int targetWidth = 200;
        int targetHeight = 150;
        try {
            if (fmt != null && MyImage.canWriteFormat(fmt)) {
                MyImage.resizeImage(tempTargetFile, targetFile, targetWidth, targetHeight, fmt, true);
            } else {
                org.apache.commons.io.FileUtils.copyFile(tempTargetFile, targetFile);
            }
        } catch (IOException ex) {
            // 回退为直接复制原图
            org.apache.commons.io.FileUtils.copyFile(tempTargetFile, targetFile);
        }

        // 删除临时文件
        if (!tempTargetFile.delete()) {
            tempTargetFile.deleteOnExit();
        }

        // 更新数据库
        Word word2 = wordBo.findById(wordId);
        WordImage wordImage = new WordImage(word2, fileName, 0, 0, user);
        wordImageBo.addWordImage(wordImage, user);

        // 转换为DTO对象返回
        WordImageDto dto = new WordImageDto();
        dto.setId(wordImage.getId());
        dto.setImageFile(wordImage.getImageFile());
        dto.setHand(wordImage.getHand());
        dto.setFoot(wordImage.getFoot());
        dto.setAuthorId(wordImage.getAuthor().getId());
        dto.setWordId(wordImage.getWord().getId());
        dto.setCreateTime(wordImage.getCreateTime());
        dto.setUpdateTime(wordImage.getUpdateTime());

        return Result.success(dto);
    }

}
