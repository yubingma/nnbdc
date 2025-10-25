package beidanci.service.controller;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import javax.naming.NamingException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.xml.bind.DatatypeConverter;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.util.ObjectUtils;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.MeaningItemVo;
import beidanci.api.model.SearchWordResult;
import beidanci.api.model.WordImageDto;
import beidanci.api.model.WordVo;
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
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.po.WordImage;
import beidanci.service.store.WordCache;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.MyImage;
import beidanci.service.util.SysParamUtil;
import beidanci.service.util.Util;
import beidanci.util.Utils;

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


    @GetMapping("/searchWord.do")
    @PreAuthorize("hasAnyRole('USER','ADMIN')")
    public SearchWordResult searchWord(HttpServletRequest request, HttpServletResponse response, String userId)
            throws IOException, ParseException,
            InvalidMeaningFormatException, EmptySpellException, SQLException, NamingException, ClassNotFoundException {

        // 获取要查找的单词拼写
        Map<String, String[]> paramMap = request.getParameterMap();
        String spell = paramMap.get("word")[0].trim();

        spell = Utils.purifySpell(spell);
        User user = userBo.findById(userId);

        if (ObjectUtils.isEmpty(spell)) {
            return new SearchWordResult(null, null, null, false);
        }

        // 获取一个单词
        String[] excludeFields = new String[] {
                "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords", "WordImageVo.word",
                "images.author.^id,displayNickName" };
        WordVo word = wordCache.getWordBySpell2(spell, excludeFields);
        if (word == null && spell.endsWith("s")) {// 如birds
            word = wordCache.getWordBySpell2(spell.substring(0, spell.length() - 1), excludeFields);
        }
        if (word == null && spell.endsWith("es")) { // 如indexes
            word = wordCache.getWordBySpell2(spell.substring(0, spell.length() - 2), excludeFields);
        }
        if (word == null && (spell.endsWith("'s") || spell.endsWith("'s"))) { // 如government's
            word = wordCache.getWordBySpell2(spell.substring(0, spell.length() - 2), excludeFields);
        }
        if (word == null && spell.endsWith("ies")) {// 如opportunities
            word = wordCache.getWordBySpell2(spell.substring(0, spell.length() - 3) + "y", excludeFields);
        }
        if (word == null && spell.endsWith("ied")) {// 如presignified
            word = wordCache.getWordBySpell2(spell.substring(0, spell.length() - 3) + "y", excludeFields);
        }
        if (word == null && spell.endsWith("ed")) {// 如tested
            word = wordCache.getWordBySpell2(spell.substring(0, spell.length() - 2), excludeFields);
        }
        if (word == null && spell.endsWith("ed")) {// 如improved
            word = wordCache.getWordBySpell2(spell.substring(0, spell.length() - 1), excludeFields);
        }
        if (word == null && spell.endsWith("ing")) {// 如testing
            word = wordCache.getWordBySpell2(spell.substring(0, spell.length() - 3), excludeFields);
        }
        if (word == null && spell.endsWith("ing")) {// 如manufacturing
            word = wordCache.getWordBySpell2(spell.substring(0, spell.length() - 3) + "e", excludeFields);
        }

        SearchWordResult result;
        if (word != null) {
            // 追加形近词（浅拷贝，避免递归过深）
            try {
                Word wordPo = wordBo.findById(word.getId(), false);
                if (wordPo != null && wordPo.getSimilarWords() != null) {
                    List<WordVo> similarWords = new ArrayList<>(wordPo.getSimilarWords().size());
                    for (Word sw : wordPo.getSimilarWords()) {
                        WordVo vo = new WordVo();
                        vo.setSpell(sw.getSpell());
                        // 仅带少量释义项，避免响应过大
                        List<MeaningItemVo> meaningItemVos = BeanUtils.makeVos(sw.getMeaningItems(), MeaningItemVo.class,
                                new String[] { "synonyms", "DictVo.owner", "DictVo.dictWords", "sentences", "createTime",
                                        "updateTime" });
                        vo.setMeaningItems(meaningItemVos);
                        vo = Util.shrinkWordVo(vo, Integer.MAX_VALUE, false);
                        similarWords.add(vo);
                    }
                    word.setSimilarWords(similarWords);
                }
            } catch (Exception ignore) {
                // ignore
            }
            // 为例句附加UGC信息
            // List<SentenceVo> sentencesWithUGC =
            // attatchChinesesForSentences(word.getSentences(), new String[]{"invitedBy",
            // "userGames", "studyGroups"});

            // 改为返回所有释义项（通用 + 词书），仅做轻量收缩
            word = Util.shrinkWordVoKeepAll(word, Integer.MAX_VALUE, false);

            result = new SearchWordResult(word, Utils.getFileNameOfWordSound(word.getSpell()),
                    (user != null) ? selectedDictBo.isWordInMySelectedDicts(word, user) : false,
                    (user != null) && dictWordBo.isWordInRawWordDict(user, word.getId()));
        } else {
            result = new SearchWordResult(null, null, null, false);
        }

        return result;
    }

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
