package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.GameHallVo;
import beidanci.api.model.WordVo;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.Dict;
import beidanci.service.po.GameHall;
import beidanci.service.po.Word;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.Util;

@Service
@Transactional(rollbackFor = Throwable.class)
public class GameHallBo extends BaseBo<GameHall> {

        @PostConstruct
    public void init() {
        setDao(new BaseDao<GameHall>() {
        });
    }

    public GameHallVo getGameHallVoById(String id) {
        GameHall gameHall = findById(id);
        GameHallVo vo = BeanUtils.makeVo(gameHall, GameHallVo.class,
                new String[]{"GameHallVo.hallGroup", "dictWords"});
        return vo;
    }

    /**
     * 获游戏大厅所包含的单词书中的所有单词
     *
     * @param id
     * @return
     */
    public Map<String/*spell*/, WordVo> getGameHallWords(String id) {
        GameHall gameHall = findById(id);
        List<Dict> dicts = gameHall.getDictGroup().getAllDicts();
        List<String> dictIds = dicts.stream().map(d -> d.getId()).collect(java.util.stream.Collectors.toList());
        String hql = "from Word w where exists (" +
                "from DictWord dw where dw.word.id=w.id and dw.dict.id in (:dictIds)" +
                ")";
        Query<Word> query = getSession().createQuery(hql, Word.class);
        query.setParameter("dictIds", dictIds);
        List<Word> words = query.list();

        Map<String, WordVo> wordsBySpell = new HashMap<>();
        for (Word word : words) {
            WordVo wordVo = BeanUtils.makeVo(word, WordVo.class,
                    new String[]{"WordVo.^id,spell,meaningItems", "MeaningItemVo.^ciXing,meaning,dict", "DictVo.^id"});
            WordVo wordVo2 = new WordVo();
            org.springframework.beans.BeanUtils.copyProperties(wordVo, wordVo2);
            wordVo2 = Util.shrinkWordVo(wordVo2, dicts, 1, true);
            wordsBySpell.put(wordVo2.getSpell(), wordVo2);
        }
        return wordsBySpell;
    }
}
