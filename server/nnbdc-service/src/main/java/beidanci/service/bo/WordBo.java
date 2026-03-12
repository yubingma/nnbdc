package beidanci.service.bo;
import java.io.File;
import java.io.IOException;
import java.util.Iterator;
import java.util.List;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.MeaningItemVo;
import beidanci.api.model.SimilarWordDto;
import beidanci.api.model.WordDto;
import beidanci.api.model.WordImageDto;
import beidanci.api.model.WordVo;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.MeaningItem;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.store.WordCache;
import beidanci.service.util.SysParamUtil;
import beidanci.util.Constants;
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
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

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
        String sql = "SELECT * FROM word ORDER BY LOWER(spell) ASC";
        return namedParameterJdbcTemplate.query(sql, 
            new EntityRowMapper<>(Word.class));
    }

    public WordVo getWordVoById(String wordId, String[] excludeFields) {
        Word word = findById(wordId, false);

        WordVo vo = word2Vo(word, excludeFields);
        return vo;
    }

    public Word getWordBySpell(String spell) {
        String sql = "SELECT * FROM word WHERE spell = :spell";
        MapSqlParameterSource params = new MapSqlParameterSource("spell", spell);
        List<Word> results = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(Word.class));
        return results.isEmpty() ? null : results.get(0);
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
                
                // 设置所有者：优先使用 Vo 传入的，否则默认为系统管理员
                User owner = new User();
                owner.setId(itemVo.getOwnerId() != null ? itemVo.getOwnerId() : Constants.SYS_USER_SYS_ID);
                item.setOwner(owner);
                
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



    public List<WordDto> getWordsOfDict(String dictId) {
        // 通用词典现在也有dict_word记录，统一查询逻辑
        String sql = "SELECT id, america_pronounce, british_pronounce, group_info, long_desc, short_desc, popularity, pronounce, spell, create_time, update_time FROM word w WHERE w.id IN (SELECT dw.word_id FROM dict_word dw WHERE dw.dict_id=:dictId)";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        
        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            WordDto wordDto = new WordDto();
            wordDto.setId(rs.getString("id"));
            wordDto.setAmericaPronounce(rs.getString("america_pronounce"));
            wordDto.setBritishPronounce(rs.getString("british_pronounce"));
            wordDto.setGroupInfo(rs.getString("group_info"));
            wordDto.setLongDesc(rs.getString("long_desc"));
            wordDto.setShortDesc(rs.getString("short_desc"));
            wordDto.setPopularity(rs.getObject("popularity", Integer.class));
            wordDto.setPronounce(rs.getString("pronounce"));
            wordDto.setSpell(rs.getString("spell"));
            wordDto.setCreateTime(rs.getTimestamp("create_time"));
            wordDto.setUpdateTime(rs.getTimestamp("update_time"));
            return wordDto;
        });
    }

    public List<SimilarWordDto> getSimilarWordsOfDict(String dictId) {
        // 通用词典现在也有dict_word记录，统一查询逻辑
        String sql = "SELECT sw.word_id, sw.similar_word_id, sw.distance, w.spell FROM similar_word sw LEFT JOIN word w ON w.id=sw.similar_word_id WHERE sw.word_id IN (SELECT dw.word_id FROM dict_word dw WHERE dw.dict_id=:dictId)";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        
        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            SimilarWordDto wordDto = new SimilarWordDto();
            wordDto.setWordId(rs.getString("word_id"));
            wordDto.setSimilarWordId(rs.getString("similar_word_id"));
            wordDto.setDistance(rs.getObject("distance", Integer.class));
            wordDto.setSimilarWordSpell(rs.getString("spell"));
            return wordDto;
        });
    }

    public List<WordImageDto> getWordImagesOfDict(String dictId) {
        // 通用词典现在也有dict_word记录，统一查询逻辑
        String sql = "SELECT id, foot, hand, image_file, author_id, word_id, create_time, update_time FROM word_image wi WHERE wi.word_id IN (SELECT dw.word_id FROM dict_word dw WHERE dw.dict_id=:dictId)";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        
        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            WordImageDto wordImageDto = new WordImageDto();
            wordImageDto.setId(rs.getString("id"));
            wordImageDto.setFoot(rs.getObject("foot", Integer.class));
            wordImageDto.setHand(rs.getObject("hand", Integer.class));
            wordImageDto.setImageFile(rs.getString("image_file"));
            wordImageDto.setAuthorId(rs.getString("author_id"));
            wordImageDto.setWordId(rs.getString("word_id"));
            wordImageDto.setCreateTime(rs.getTimestamp("create_time"));
            wordImageDto.setUpdateTime(rs.getTimestamp("update_time"));
            return wordImageDto;
        });
    }

}
