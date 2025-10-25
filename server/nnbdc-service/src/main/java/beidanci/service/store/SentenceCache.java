package beidanci.service.store;

import java.io.IOException;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import beidanci.api.Result;
import beidanci.api.model.SentenceVo;
import beidanci.api.model.UserVo;
import beidanci.service.bo.SentenceBo;
import beidanci.service.bo.WordSentenceBo;
import beidanci.service.error.ErrorCode;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.Sentence;
import beidanci.service.po.User;
import beidanci.service.po.WordSentence;
import beidanci.service.util.Util;

/**
 * 管理系统中所有例句
 *
 * @author Administrator
 */
@Component
public class SentenceCache {
    private final ConcurrentHashMap<String, ConcurrentHashMap<SentenceVo, Object>> sentencesByWord = new ConcurrentHashMap<>();

    private final ConcurrentHashMap<String, SentenceVo> sentencesById = new ConcurrentHashMap<>();

    @Autowired
    SentenceBo sentenceBo;


    @Autowired
    WordSentenceBo wordSentenceBo;


    private SentenceVo sentence2Vo(final Sentence sentence) {
        String english = sentence.getEnglish();
        User author = sentence.getAuthor();
        UserVo authorVo = new UserVo();
        authorVo.setId(author.getId());
        authorVo.setUserName(author.getUserName());
        authorVo.setDisplayNickName(author.getDisplayNickName());

        return new SentenceVo(sentence.getId(), english, sentence.getChinese(), sentence.getTheType(),
                sentence.getEnglishDigest(), sentence.getHandCount(), sentence.getFootCount(), authorVo);
    }

    public void putSentenceToCache(final SentenceVo sentence, boolean addToWordForcelly) {
        // 把例句加入到Map（按ID）
        sentencesById.put(sentence.getId(), sentence);

        // 把例句拆分成若干单词，并加入到Map(按单词)
        List<String> words = Util.splitSentence2Words(sentence.getEnglish());
        for (String spell : words) {
            if (!sentencesByWord.containsKey(spell)) {
                synchronized (sentencesByWord) {
                    if (!sentencesByWord.containsKey(spell)) {
                        ConcurrentHashMap<SentenceVo, Object> sentenceVos = new ConcurrentHashMap<>();
                        sentencesByWord.put(spell, sentenceVos);
                    }
                }
            }
            ConcurrentHashMap<SentenceVo, Object> sentenceVos = sentencesByWord.get(spell);
            if (addToWordForcelly || sentenceVos.size() < 100) { // 单词超过100个例句则不再添加，提高启动性能
                sentenceVos.put(sentence, sentence);
            }
        }
    }

    public void reloadSentence(String sentenceId) throws InvalidMeaningFormatException, EmptySpellException, ParseException, IOException {
        // 从缓存中移除例句
        removeSentenceFromCache(sentenceId);

        // 重新从数据库加载例句到缓存
        Sentence sentence = sentenceBo.findById(sentenceId);
        SentenceVo sentenceVo = sentence2Vo(sentence);
        putSentenceToCache(sentenceVo, true);
    }

    /**
     * 从缓存中移除例句
     *
     * @param sentenceId
     */
    public void removeSentenceFromCache(String sentenceId) throws InvalidMeaningFormatException, EmptySpellException, ParseException, IOException {
        SentenceVo existing = getSentenceById(sentenceId);
        if (existing != null) {
            // 把例句从缓存清除
            List<String> dynamicLinkedWords = Util.splitSentence2Words(existing.getEnglish());
            for (String word : dynamicLinkedWords) {
                sentencesByWord.get(word).remove(existing);
            }
            sentencesById.remove(sentenceId);
        }
    }


    public HashSet<SentenceVo> getSentencesOfWord(String spell) {
        HashSet<SentenceVo> sentences = new HashSet<>();
        for (String word : Util.getVariantsOfWord(spell)) {
            ConcurrentHashMap<SentenceVo, Object> sents = sentencesByWord.get(word);
            if (sents != null) {
                sentences.addAll(sents.keySet());
            }
        }
        return sentences;
    }

    public SentenceVo getSentenceById(String id) {
        return sentencesById.get(id);
    }

    public void refreshSentenceVo(SentenceVo newVo) {
        SentenceVo old = getSentenceById(newVo.getId());
        old.setEnglish(newVo.getEnglish());
    }

    public List<WordSentence> getWordLinksOfASentence(String sentenceId) {
        Sentence sentence = sentenceBo.findById(sentenceId);
        if (sentence == null) {
            throw new RuntimeException("sentence id 不存在: " + sentenceId);
        }

        List<WordSentence> wordLinks = wordSentenceBo.getWordLinksOfSentence(sentence);
        return wordLinks;
    }


    /**
     * 检查例句缓存是否有问题
     */
    public Result<List<SentenceVo>> check() {
        List<SentenceVo> vos = new LinkedList<>();
        for (SentenceVo vo : sentencesById.values()) {
            if (vo.getId() == null) {
                vos.add(vo);
            }
        }
        if (!vos.isEmpty()) {
            return new Result<>(ErrorCode.CODE_BAD_SENTENCE, String.format("foud %s sentences whose id is null", vos.size()), vos);
        }

        vos = new LinkedList<>();
        for (ConcurrentHashMap<SentenceVo, Object> map : sentencesByWord.values()) {
            for (Map.Entry<SentenceVo, Object> entry : map.entrySet()) {
                SentenceVo vo = entry.getKey();
                if (vo.getId() == null) {
                    vos.add(vo);
                }
            }
        }
        if (!vos.isEmpty()) {
            return new Result<>(ErrorCode.CODE_BAD_SENTENCE, String.format("foud %s sentences whose id is null!", vos.size()), vos);
        }

        return Result.success(null);
    }
}
