package beidanci.service.bo;
import javax.annotation.PostConstruct;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.Sentence;
import beidanci.service.po.Word;
import beidanci.service.po.WordSentence;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional(rollbackFor = Throwable.class)
public class WordSentenceBo extends BaseBo<WordSentence> {

        @PostConstruct
    public void init() {
        setDao(new BaseDao<WordSentence>() {
        });
    }

    public List<WordSentence> getSentenceLinksOfWord(Word word) {
        WordSentence exam = new WordSentence();
        exam.setWord(word);
        return queryAll(exam, false);
    }

    public List<WordSentence> getWordLinksOfSentence(Sentence sentence) {
        WordSentence exam = new WordSentence();
        exam.setSentence(sentence);
        return queryAll(exam, false);
    }
}
