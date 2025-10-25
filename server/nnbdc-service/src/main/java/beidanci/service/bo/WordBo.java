package beidanci.service.bo;
import java.io.File;
import java.io.IOException;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.Date;
import java.util.Iterator;
import java.util.List;

import javax.annotation.PostConstruct;

import org.hibernate.query.Query;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.MeaningItemVo;
import beidanci.api.model.SimilarWordDto;
import beidanci.api.model.WordDto;
import beidanci.api.model.WordImageDto;
import beidanci.api.model.WordList;
import beidanci.api.model.WordVo;
import beidanci.service.dao.BaseDao;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.Dict;
import beidanci.service.po.MeaningItem;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.po.WrongWord;
import beidanci.service.store.WordCache;
import beidanci.service.util.SysParamUtil;
import beidanci.util.Utils;
@Service
@Transactional(rollbackFor = Throwable.class)
public class WordBo extends BaseBo<Word> {
    @Autowired
    WordCache wordCache;

    @Autowired
    MeaningItemBo meaningItemBo;
    @Autowired
    SysParamUtil sysParamUtil;

    @Autowired
    WrongWordBo wrongWordBo;

    @Autowired
    LearningWordBo learningWordBo;

    @Autowired
    DictBo dictBo;

    @Autowired
    UserBo userBo;

        @PostConstruct
    public void init() {
        setDao(new BaseDao<Word>() {
        });
    }

    /**
     * 获取所有单词，并按照单词拼写升序排列(不区分大小写)
     *
     * @return
     */
    public List<Word> getAllWords() {
        String hql = "from Word order by lower(spell) asc";
        Query<Word> query = getSession().createQuery(hql, Word.class);
        return query.list();
    }

    public WordVo getWordVoById(String wordId, String[] excludeFields) {
        Word word = findById(wordId, false);

        WordVo vo = word2Vo(word, excludeFields);
        return vo;
    }

    public Word getWordBySpell(String spell) {
        String hql = "from Word w where w.spell = :spell";
        Query<Word> query = getSession().createQuery(hql, Word.class);
        query.setParameter("spell", spell);
        return query.uniqueResult();
    }

    public WordVo getWordVoBySpell(String spell, String[] excludeFields) {
        Word word = getWordBySpell(spell);

        if (word == null) {
            return null;
        }
        WordVo vo = word2Vo(word, excludeFields);
        return vo;
    }

    private WordVo word2Vo(Word word, String[] excludeFields) {
        WordVo vo = WordCache.genWordVO(word, excludeFields);

        // 不再额外查询数据库，问题应在PO->VO转换链上修复
        return vo;
    }

    private MeaningItemVo getMeaningItemVoFromList(String meaningItemId, List<MeaningItemVo> meaningItems) {
        for (MeaningItemVo itemVo : meaningItems) {
            if (itemVo.getId() != null && itemVo.getId().equals(meaningItemId)) {
                return itemVo;
            }
        }
        return null;
    }


    public String updateWord(WordVo wordVo, String reason) throws IllegalAccessException, InvalidMeaningFormatException,
            EmptySpellException, IOException, ParseException {
        if (wordVo.getId() == null) {
            return "单词ID不能为null";
        }

        WordVo existingWord = wordCache.getWordBySpell(wordVo.getSpell(), new String[] {
                "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords" });
        if (existingWord != null && !existingWord.getId().equals(wordVo.getId())) {
            return String.format("单词%s已存在", wordVo.getSpell());
        }

        Word word = findById(wordVo.getId());

        // 删除被删除的meaningItems
        for (Iterator<MeaningItem> i = word.getMeaningItems().iterator(); i.hasNext();) {
            MeaningItem item = i.next();
            if (getMeaningItemVoFromList(item.getId(), wordVo.getMeaningItems()) == null) {
                i.remove();
                meaningItemBo.deleteEntity(item);
            }
        }

        // 更新被修改的meaningItems
        for (MeaningItem item : word.getMeaningItems()) {
            MeaningItemVo itemVo = getMeaningItemVoFromList(item.getId(), wordVo.getMeaningItems());
            if (itemVo != null) {
                item.setCiXing(itemVo.getCiXing());
                item.setMeaning(itemVo.getMeaning());
                meaningItemBo.updateEntity(item);
            }
        }

        // 添加新增的meaningItems
        for (MeaningItemVo itemVo : wordVo.getMeaningItems()) {
            if (itemVo.getId() == null) {
                MeaningItem item = new MeaningItem();
                item.setCiXing(itemVo.getCiXing());
                item.setMeaning(itemVo.getMeaning());
                item.setWord(word);
                meaningItemBo.createEntity(item);
                word.getMeaningItems().add(item);
            }
        }

        // 更新单词的拼写
        String oldSpell = word.getSpell();
        word.setSpell(wordVo.getSpell());

        updateEntity(word);

        // 更新声音文件（重命名）
        if (!oldSpell.equalsIgnoreCase(wordVo.getSpell())) {
            File oldSoundFile = new File(
                    sysParamUtil.getSoundPath() + "/" + Utils.getFileNameOfWordSound(oldSpell) + ".mp3");
            File newSoundFile = new File(
                    sysParamUtil.getSoundPath() + "/" + Utils.getFileNameOfWordSound(wordVo.getSpell()) + ".mp3");
            oldSoundFile.renameTo(newSoundFile);

            oldSoundFile = new File(
                    sysParamUtil.getSoundPath() + "/" + Utils.getFileNameOfWordSound(oldSpell) + ".oga");
            newSoundFile = new File(
                    sysParamUtil.getSoundPath() + "/" + Utils.getFileNameOfWordSound(wordVo.getSpell()) + ".oga");
            if (oldSoundFile.exists()) {
                oldSoundFile.renameTo(newSoundFile);
            }
        }

        return null;
    }

    public List<WordList> getWordLists(String userId) {
        User user = userBo.findById(userId);
        List<WordList> wordLists = new ArrayList<>();
        WrongWord wrongWord = new WrongWord(null, user);
        wordLists.add(new WordList("今日错词", wrongWordBo.pagedQuery(wrongWord, 1, 1).getTotal()));

        wordLists
                .add(new WordList("今日新词", learningWordBo.getTodayNewWordsForAPage2(0, 1, user, new Date()).getTotal()));
        wordLists
                .add(new WordList("今日旧词", learningWordBo.getTodayOldWordsForAPage2(0, 1, user, new Date()).getTotal()));
        wordLists.add(new WordList("今日单词", learningWordBo.getTodayWordsForAPage2(0, 1, user, new Date()).getTotal()));
        wordLists.add(new WordList("学习中", learningWordBo.getLearningWordsForAPage2(0, 1, user).getTotal()));

        Dict rawWordDict = dictBo.getRawWordDict(user);
        wordLists.add(new WordList("生词本", rawWordDict.getWordCount()));

        wordLists.add(new WordList("已掌握", user.getMasteredWordsCount()));

        return wordLists;
    }

    public List<WordDto> getWordsOfDict(String dictId) {
        // 通用词典现在也有dict_word记录，统一查询逻辑
        String hql = "select id, americaPronounce, britishPronounce, groupInfo, longDesc, shortDesc, popularity, pronounce, spell, createTime, updateTime from word w where w.id in (select dw.wordId from dict_word dw where dw.dictId=:dictId)";
        Query<?> query = getSession().createNativeQuery(hql);
        List<?> results = query.setParameter("dictId", dictId).list();

        List<WordDto> wordDtos = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            WordDto wordDto = new WordDto();
            wordDto.setId((String) tuple[0]);
            wordDto.setAmericaPronounce((String) tuple[1]);
            wordDto.setBritishPronounce((String) tuple[2]);
            wordDto.setGroupInfo((String) tuple[3]);
            wordDto.setLongDesc((String) tuple[4]);
            wordDto.setShortDesc((String) tuple[5]);
            wordDto.setPopularity((Integer) tuple[6]);
            wordDto.setPronounce((String) tuple[7]);
            wordDto.setSpell((String) tuple[8]);
            wordDto.setCreateTime((Timestamp) tuple[9]);
            wordDto.setUpdateTime((Timestamp) tuple[10]);
            wordDtos.add(wordDto);
        }
        return wordDtos;
    }

    public List<SimilarWordDto> getSimilarWordsOfDict(String dictId) {
        // 通用词典现在也有dict_word记录，统一查询逻辑
        String hql = "select sw.wordId, sw.similarWordId, sw.distance, w.spell from similar_word sw left join word w on w.id=sw.similarWordId where sw.wordId in (select dw.wordId from dict_word dw where dw.dictId=:dictId)";
        Query<?> query = getSession().createNativeQuery(hql);
        List<?> results = query.setParameter("dictId", dictId).list();
        
        List<SimilarWordDto> words = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            SimilarWordDto wordDto = new SimilarWordDto();
            wordDto.setWordId((String) tuple[0]);
            wordDto.setSimilarWordId((String) tuple[1]);
            wordDto.setDistance((Integer) tuple[2]);
            wordDto.setSimilarWordSpell((String) tuple[3]);
            words.add(wordDto);
        }
        return words;
    }

    public List<WordImageDto> getWordImagesOfDict(String dictId) {
        // 通用词典现在也有dict_word记录，统一查询逻辑
        String sql = "select id, foot, hand, imageFile, authorId, wordId, createTime, updateTime from word_image wi where wi.wordId in (select dw.wordId from dict_word dw where dw.dictId=:dictId)";
        Query<?> query = getSession().createNativeQuery(sql);
        query.setParameter("dictId", dictId);
        List<?> results = query.list();

        List<WordImageDto> wordImageDtos = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            WordImageDto wordImageDto = new WordImageDto();
            wordImageDto.setId((String) tuple[0]);
            wordImageDto.setFoot((Integer) tuple[1]);
            wordImageDto.setHand((Integer) tuple[2]);
            wordImageDto.setImageFile((String) tuple[3]);
            wordImageDto.setAuthorId((String) tuple[4]);
            wordImageDto.setWordId((String) tuple[5]);
            wordImageDto.setCreateTime((Timestamp) tuple[6]);
            wordImageDto.setUpdateTime((Timestamp) tuple[7]);
            wordImageDtos.add(wordImageDto);
        }
        return wordImageDtos;
    }

}
