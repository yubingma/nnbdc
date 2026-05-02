package beidanci.service.bo;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.AiStory;
import org.apache.commons.lang3.tuple.Pair;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.PostConstruct;

@Service
@Transactional(rollbackFor = Throwable.class)
public class AiStoryBo extends BaseBo<AiStory> {

    @PostConstruct
    public void init() {
        setDao(new BaseDao<AiStory>() {
        });
    }

    public AiStory findByWordsHash(String wordsHash) {
        return queryUnique("SELECT * FROM ai_story WHERE words_hash = :wordsHash", Pair.of("wordsHash", wordsHash));
    }
}
