package beidanci.service.bo;
import java.io.File;
import java.io.IOException;
import java.util.Iterator;
import java.util.List;
import java.util.Date;

import javax.annotation.PostConstruct;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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
import beidanci.service.util.Util;
@Service
@Transactional(rollbackFor = Throwable.class)
public class WordBo extends BaseBo<Word> {
    private static final Logger log = LoggerFactory.getLogger(WordBo.class);

    @Autowired
    WordCache wordCache;

    @Autowired
    MeaningItemBo meaningItemBo;
    @Autowired
    SysParamUtil sysParamUtil;
    @Autowired
    private AiBo aiBo;

    @Autowired
    private SysDbSyncBo sysDbSyncBo;



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
                item.setCiXing(Util.sanitizeAiString(itemVo.getCiXing()));
                item.setMeaning(Util.sanitizeAiString(itemVo.getMeaning()));
                meaningItemBo.updateEntity(item);
            }
        }

        // 添加新增的meaningItems
        for (MeaningItemVo itemVo : wordVo.getMeaningItems()) {
            if (itemVo.getId() == null) {
                MeaningItem item = new MeaningItem();
                item.setCiXing(Util.sanitizeAiString(itemVo.getCiXing()));
                item.setMeaning(Util.sanitizeAiString(itemVo.getMeaning()));
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
        return getWordsOfDictBySeqRange(dictId, null, null);
    }

    public List<WordDto> getWordsOfDictBySeqRange(String dictId, Integer fromSeq, Integer toSeq) {
        StringBuilder sql = new StringBuilder("SELECT id, america_pronounce, british_pronounce, group_info, long_desc, short_desc, popularity, pronounce, spell, vec_x, vec_y, vec_z, create_time, update_time FROM word w WHERE w.id IN (SELECT dw.word_id FROM dict_word dw WHERE dw.dict_id=:dictId");
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        if (fromSeq != null) {
            sql.append(" AND dw.seq >= :fromSeq");
            params.addValue("fromSeq", fromSeq);
        }
        if (toSeq != null) {
            sql.append(" AND dw.seq <= :toSeq");
            params.addValue("toSeq", toSeq);
        }
        sql.append(")");
        
        String querySql = java.util.Objects.requireNonNull(sql.toString());
        return namedParameterJdbcTemplate.query(querySql, params, (rs, rowNum) -> {
            WordDto wordDto = new WordDto();
            String idStr = rs.getString("id");
            assert idStr != null;
            wordDto.setId(idStr);
            wordDto.setAmericaPronounce(rs.getString("america_pronounce"));
            wordDto.setBritishPronounce(rs.getString("british_pronounce"));
            wordDto.setGroupInfo(rs.getString("group_info"));
            wordDto.setLongDesc(rs.getString("long_desc"));
            wordDto.setShortDesc(rs.getString("short_desc"));
            wordDto.setPopularity(rs.getObject("popularity", Integer.class));
            wordDto.setPronounce(rs.getString("pronounce"));
            wordDto.setSpell(rs.getString("spell"));
            wordDto.setVecX(rs.getObject("vec_x", Float.class));
            wordDto.setVecY(rs.getObject("vec_y", Float.class));
            wordDto.setVecZ(rs.getObject("vec_z", Float.class));
            wordDto.setCreateTime(rs.getTimestamp("create_time"));
            wordDto.setUpdateTime(rs.getTimestamp("update_time"));
            return wordDto;
        });
    }

    public List<SimilarWordDto> getSimilarWordsOfDict(String dictId) {
        return getSimilarWordsOfDictBySeqRange(dictId, null, null);
    }

    public List<SimilarWordDto> getSimilarWordsOfDictBySeqRange(String dictId, Integer fromSeq, Integer toSeq) {
        StringBuilder sql = new StringBuilder("SELECT sw.word_id, sw.similar_word_id, sw.distance, w.spell, sw.create_time, sw.update_time " +
                     "FROM similar_word sw LEFT JOIN word w ON w.id=sw.similar_word_id " +
                     "WHERE sw.word_id IN (SELECT dw.word_id FROM dict_word dw WHERE dw.dict_id=:dictId");
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        if (fromSeq != null) {
            sql.append(" AND dw.seq >= :fromSeq");
            params.addValue("fromSeq", fromSeq);
        }
        if (toSeq != null) {
            sql.append(" AND dw.seq <= :toSeq");
            params.addValue("toSeq", toSeq);
        }
        sql.append(")");
        
        String querySql = java.util.Objects.requireNonNull(sql.toString());
        return namedParameterJdbcTemplate.query(querySql, params, (rs, rowNum) -> {
            SimilarWordDto wordDto = new SimilarWordDto();
            String wordIdStr = rs.getString("word_id");
            assert wordIdStr != null;
            wordDto.setWordId(wordIdStr);
            String similarWordIdStr = rs.getString("similar_word_id");
            assert similarWordIdStr != null;
            wordDto.setSimilarWordId(similarWordIdStr);
            Integer distance = rs.getObject("distance", Integer.class);
            wordDto.setDistance(distance != null ? distance : 0);
            String spell = rs.getString("spell");
            wordDto.setSimilarWordSpell(spell != null ? spell : "");
            Date createTime = rs.getTimestamp("create_time");
            wordDto.setCreateTime(createTime != null ? createTime : new Date());
            Date updateTime = rs.getTimestamp("update_time");
            wordDto.setUpdateTime(updateTime != null ? updateTime : (createTime != null ? createTime : new Date()));
            return wordDto;
        });
    }

    public List<WordImageDto> getWordImagesOfDict(String dictId) {
        return getWordImagesOfDictBySeqRange(dictId, null, null);
    }

    public List<WordImageDto> getWordImagesOfDictBySeqRange(String dictId, Integer fromSeq, Integer toSeq) {
        StringBuilder sql = new StringBuilder("SELECT id, foot, hand, image_file, author_id, word_id, create_time, update_time FROM word_image wi WHERE wi.word_id IN (SELECT dw.word_id FROM dict_word dw WHERE dw.dict_id=:dictId");
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        if (fromSeq != null) {
            sql.append(" AND dw.seq >= :fromSeq");
            params.addValue("fromSeq", fromSeq);
        }
        if (toSeq != null) {
            sql.append(" AND dw.seq <= :toSeq");
            params.addValue("toSeq", toSeq);
        }
        sql.append(")");
        
        String querySql = java.util.Objects.requireNonNull(sql.toString());
        return namedParameterJdbcTemplate.query(querySql, params, (rs, rowNum) -> {
            WordImageDto wordImageDto = new WordImageDto();
            String idStr = rs.getString("id");
            assert idStr != null;
            wordImageDto.setId(idStr);
            wordImageDto.setFoot(rs.getObject("foot", Integer.class));
            wordImageDto.setHand(rs.getObject("hand", Integer.class));
            wordImageDto.setImageFile(rs.getString("image_file"));
            wordImageDto.setAuthorId(rs.getString("author_id"));
            String wordIdStr = rs.getString("word_id");
            assert wordIdStr != null;
            wordImageDto.setWordId(wordIdStr);
            wordImageDto.setCreateTime(rs.getTimestamp("create_time"));
            wordImageDto.setUpdateTime(rs.getTimestamp("update_time"));
            return wordImageDto;
        });
    }

    public void regeneratePronunciation(String wordId) throws Exception {
        Word word = findById(wordId);
        if (word == null) {
            throw new RuntimeException("Word not found: " + wordId);
        }

        String spell = word.getSpell();
        String pureSpell = Utils.uniformSpellForFilename(spell);
        if (pureSpell.length() == 0) return;

        String firstChar = pureSpell.substring(0, 1);
        File dir = new File(sysParamUtil.getSoundPath() + "/" + firstChar);
        if (!dir.exists()) dir.mkdirs();
        File soundFile = new File(dir, pureSpell + ".mp3");

        // Try Youdao first
        try {
            String[] urlStrs = {
                    "http://dict.youdao.com/dictvoice?type=2&audio=" + java.net.URLEncoder.encode(pureSpell, "UTF-8"),
                    "http://dict.youdao.com/dictvoice?type=1&audio=" + java.net.URLEncoder.encode(pureSpell, "UTF-8"),
                    "http://dict.youdao.com/dictvoice?le=eng&audio=" + java.net.URLEncoder.encode(pureSpell, "UTF-8")
            };

            boolean success = false;
            for (String urlStr : urlStrs) {
                java.net.HttpURLConnection conn = (java.net.HttpURLConnection) new java.net.URL(urlStr).openConnection();
                conn.setRequestMethod("GET");
                conn.setConnectTimeout(3000);
                conn.setReadTimeout(5000);

                if (conn.getResponseCode() == 200) {
                    try (java.io.InputStream is = conn.getInputStream();
                         java.io.FileOutputStream fos = new java.io.FileOutputStream(soundFile)) {
                        byte[] buffer = new byte[4096];
                        int bytesRead;
                        while ((bytesRead = is.read(buffer)) != -1) {
                            fos.write(buffer, 0, bytesRead);
                        }
                        fos.flush();
                    }
                    log.info("Successfully fetched pronunciation from Youdao for word: " + spell);
                    success = true;
                    break;
                }
            }

            if (!success) {
                throw new RuntimeException("All youdao URLs failed");
            }
        } catch (Exception e) {
            log.warn("Failed to fetch pronunciation from Youdao for word: " + spell + ", falling back to AI TTS. Error: " + e.getMessage());
            // Fallback to AI
            byte[] audioData = aiBo.generateSpeech(spell, null, null).audioData;
            if (audioData != null && audioData.length > 0) {
                try (java.io.FileOutputStream fos = new java.io.FileOutputStream(soundFile)) {
                    fos.write(audioData);
                    fos.flush();
                }
                log.info("Successfully generated AI pronunciation for word: " + spell);
            } else {
                throw new RuntimeException("Failed to generate AI pronunciation for word: " + spell);
            }
        }

        // 记录同步日志，并更新数据库中的 update_time
        word.setUpdateTime(new Date());
        updateEntity(word);
        sysDbSyncBo.logOperation(word, "UPDATE", "word", word.getId(), beidanci.service.util.JsonUtils.toJson(toDto(word)));
    }

    public WordDto toDto(Word word) {
        WordDto dto = new WordDto();
        dto.setId(word.getId());
        dto.setSpell(word.getSpell());
        dto.setAmericaPronounce(word.getAmericaPronounce());
        dto.setBritishPronounce(word.getBritishPronounce());
        dto.setPronounce(word.getPronounce());
        dto.setPopularity(word.getPopularity());
        dto.setGroupInfo(word.getGroupInfo());
        dto.setShortDesc(word.getShortDesc());
        dto.setLongDesc(word.getLongDesc());
        dto.setVecX(word.getVecX());
        dto.setVecY(word.getVecY());
        dto.setVecZ(word.getVecZ());
        dto.setCreateTime(word.getCreateTime());
        dto.setUpdateTime(word.getUpdateTime());
        return dto;
    }

    @Transactional(rollbackFor = Throwable.class)
    public void updateWordVectors(String wordId, Float vecX, Float vecY, Float vecZ) throws Exception {
        Word word = findById(wordId);
        if (word != null) {
            word.setVecX(vecX);
            word.setVecY(vecY);
            word.setVecZ(vecZ);
            word.setUpdateTime(new Date());
            updateEntity(word);
        }
    }
}
