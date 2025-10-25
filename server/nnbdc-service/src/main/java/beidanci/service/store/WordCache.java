package beidanci.service.store;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import beidanci.api.model.WordShortDescChineseVo;
import beidanci.api.model.WordVo;
import beidanci.service.bo.WordBo;
import beidanci.service.bo.WordSentenceBo;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.Word;
import beidanci.service.po.WordSentence;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.Util;

@Component
public class WordCache {
    private static final Logger log = LoggerFactory.getLogger(WordCache.class);

    /**
     * 词库中所有单词（按拼写索引）
     */
    private final Map<String, WordVo> wordsBySpell = new HashMap<>();

    @Autowired
    WordBo wordBo;

    @Autowired
    WordSentenceBo wordSentenceBo;


    private static int invalidCount = 0;

    /**
     * 验证单词是否合乎规格
     */
    private static String checkWord(WordVo word) {
        if (word.getMeaningItems().isEmpty()) {
            return "单词无释义";
        }
        return null;
    }

    public WordVo getWordBySpell(String spell, String[] excludeFields) throws IOException, ParseException, InvalidMeaningFormatException, EmptySpellException {
        return wordBo.getWordVoBySpell(spell, excludeFields);
    }

    /**
     * 根据单词拼写查找单词，如果找不到，还会对单词的大小写做一定转换，并重试
     *
     * @param spell
     * @return
     */
    public WordVo getWordBySpell2(String spell, String[] excludeFields) throws InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        WordVo word = wordsBySpell.get(spell);
        if (word == null) {
            word = getWordBySpell(spell.toLowerCase(), excludeFields);
        }
        if (word == null) {
            word = getWordBySpell(spell.toUpperCase(), excludeFields);
        }
        if (word == null) {
            word = getWordBySpell(spell.substring(0, 1).toUpperCase() + spell.substring(1), excludeFields); // 首字母转换为大写
        }
        return word;
    }

    public WordVo getWordById(String id, String[] excludeFields) {
        WordVo word = wordBo.getWordVoById(id, excludeFields);
        return word;
    }

    public int getWordCount() {
        return wordsBySpell.size();
    }


    /**
     * 获取所有单词和例句的连接，并按照单词拼写进行组织
     */
    public Map<String, List<WordSentence>> getSentenceLinksOfAllWords() {
        Map<String, List<WordSentence>> linksBySpell = new HashMap<>();
        List<WordSentence> wordSentenceLinks = wordSentenceBo.queryAll(null, false);
        for (WordSentence link : wordSentenceLinks) {
            String spell = link.getWord().getSpell();
            List<WordSentence> linksOfASpell = linksBySpell.get(spell);
            if (linksOfASpell == null) {
                linksOfASpell = new ArrayList<>();
                linksBySpell.put(spell, linksOfASpell);
            }
            linksOfASpell.add(link);
        }
        return linksBySpell;
    }

    public static WordVo genWordVO(
            Word wordPo, String[] excludeFields) {
        WordVo wordVo = BeanUtils.makeVo(wordPo, WordVo.class, excludeFields);

        // 单词英文描述的中文翻译
        List<WordShortDescChineseVo> shortDescChineses = Util
                .getWordShortDescChineses(wordPo, 3);
        wordVo.setShortDescChineses(shortDescChineses);

        // 验证单词是否合乎规格
        String errMsg = checkWord(wordVo);
        if (errMsg != null) {
            invalidCount++;
            log.info(String.format("发现词库中不合规格的单词[%s] 原因[%s] 总数[%d]", wordVo.getSpell(), errMsg, invalidCount));
        }

        return wordVo;
    }

    public Map<String, WordVo> getWordsBySpell() {
        return wordsBySpell;
    }
}
