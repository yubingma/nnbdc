package beidanci.service.controller;

import java.io.IOException;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.SentenceVo;
import beidanci.api.model.WordVo;
import beidanci.service.bo.SentenceBo;
import beidanci.service.bo.UserBo;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.Sentence;
import beidanci.service.po.User;
import beidanci.service.store.SentenceCache;
import beidanci.service.store.WordCache;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.Util;

@RestController
public class SentenceController {
    private static final Logger log = LoggerFactory.getLogger(SentenceController.class);
    @Autowired
    SentenceBo sentenceBo;

    @Autowired
    WordCache wordCache;

    @Autowired
    UserBo userBo;

    @Autowired
    SentenceCache sentenceCache;

    @PostMapping("/saveSentenceChinese.do")
    @PreAuthorize("hasAnyRole('USER','ADMIN')")
    public Result<SentenceVo> saveSentenceChinese(String sentenceId, String chinese, String currWord)
            throws IllegalArgumentException, IllegalAccessException, InvalidMeaningFormatException, EmptySpellException, ParseException, IOException {
        if (chinese == null || !StringUtils.hasText(chinese.trim())) {
            return Result.fail("例句翻译内容不能为空");
        }

        // 返回更新后的例句对象
        Sentence sentence = sentenceBo.findById(sentenceId);
        SentenceVo vo = BeanUtils.makeVo(sentence, SentenceVo.class,
                new String[]{"invitedBy", "userGames", "studyGroups"});
        shrinkSentenceVo(vo);

        return Result.success(vo);
    }

    private void shrinkSentenceVo(SentenceVo vo) throws IllegalAccessException {
        BeanUtils.setPropertiesToNull(vo.getAuthor(), new String[]{"id", "displayNickName"});
    }

    @PostMapping("/saveSentence.do")
    @PreAuthorize("hasAnyRole('USER','ADMIN')")
    public Result<SentenceVo> saveSentence(String english, String chinese, String wordId, int payCowdung, String currWord, String userId)
            throws IllegalArgumentException, IllegalAccessException, InvalidMeaningFormatException, EmptySpellException, ParseException, IOException {
        if (!StringUtils.hasText(english)) {
            return Result.fail("例句英文内容不得为空");
        }
        english = Util.replaceChineseSymbol(english);
        if (!Util.isEnglish(english)) {
            return Result.fail("例句英文内容必须是纯英文");
        }

        // 判断新例句是否包含单词
        WordVo word = wordCache.getWordById(wordId, new String[]{
                "SynonymVo.meaningItem", "SynonymVo.word",  "similarWords", "DictVo.dictWords"});
        List<String> parts = Util.splitSentence2Words(word.getSpell()); // 单词可能是短语，所以需要分割
        for (String part : parts) {
            if (part.equals("sb") || part.equals("somebody") || part.equals("sb's") || part.equals("one's")
                    || part.equals("sth") || part.equals("something")
                    || part.equals("be") || part.equals("do") || part.equals("doing")) {
                continue;
            }
            List<String> variants = Util.getVariantsOfWord(part);
            boolean contains = false;
            for (String variant : variants) {
                if (english.contains(variant)) {
                    contains = true;
                    break;
                }
            }
            if (!contains) {
                return Result.fail("例句英文内容未包含: " + part);
            }
        }

        //检测用户是否有足够的泡泡糖
        User user = userBo.findById(userId);
        if (user.getCowDung() < payCowdung) {
            return Result.fail(String.format("你的泡泡糖数量为%d，不足%d个", user.getCowDung(), payCowdung));
        }

        Sentence sentence = sentenceBo.createSentence(english, chinese, wordId, payCowdung, currWord, userId);

        // 返回更新后的例句对象
        SentenceVo vo = BeanUtils.makeVo(sentence, SentenceVo.class,
                new String[]{"invitedBy", "userGames", "studyGroups"});
        shrinkSentenceVo(vo);

        log.info(String.format("用户[%s]为单词[%s]新增了例句: %s|%s",
                user.getDisplayNickName(), word.getSpell(), english, chinese));
        return Result.success(vo);
    }

    @DeleteMapping("/deleteSentence.do")
    @PreAuthorize("hasAnyRole('USER','ADMIN')")
    public Result<Void> deleteSentence(String id, String currWord, String userId)
            throws IllegalArgumentException, InvalidMeaningFormatException, EmptySpellException, ParseException, IOException {
        return sentenceBo.deleteSentence(id, currWord, userId);
    }


    @PutMapping("/handSentence.do")
    @PreAuthorize("hasAnyRole('USER','ADMIN')")
    public Result<Integer> handSentence(String id, String currWord, String userId)
            throws IllegalArgumentException, IllegalAccessException, InvalidMeaningFormatException, EmptySpellException, ParseException, IOException {
        User user = userBo.findById(userId);
        Result<Integer> result = sentenceBo.handSentence(id, user, currWord);
        return result;
    }

    @PutMapping("/footSentence.do")
    @PreAuthorize("hasAnyRole('USER','ADMIN')") 
    public Result<Integer> footSentence(String id, String currWord, String userId)
            throws IllegalArgumentException, IllegalAccessException, InvalidMeaningFormatException, EmptySpellException, ParseException, IOException {
        User user = userBo.findById(userId);
        Result<Integer> result = sentenceBo.footSentence(id, user, currWord);
        return result;
    }

}
