package beidanci.service.bo;

import java.io.IOException;
import java.util.List;
import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.Result;
import beidanci.api.model.EventType;
import beidanci.api.model.SentenceDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.Event;
import beidanci.service.po.Sentence;
import beidanci.service.po.User;
import beidanci.service.po.WordSentence;
import beidanci.service.po.WordSentenceId;
import beidanci.service.store.SentenceCache;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.Util;

@Service
@Transactional(rollbackFor = Throwable.class)
public class SentenceBo extends BaseBo<Sentence> {
    @Autowired
    WordSentenceBo wordSentenceBo;

    @Autowired
    SentenceCache sentenceCache;

    @Autowired
    EventBo eventBo;

    @Autowired
    UserBo userBo;

    @Autowired
    SysDbSyncBo sysDbLogBo;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<Sentence>() {
        });
    }

    public List<Sentence> findAll() {
        return queryAll(null, false);
    }

    public Result<Integer> handSentence(String id, User user, String currWord)
            throws IllegalArgumentException, IllegalAccessException, InvalidMeaningFormatException, EmptySpellException,
            ParseException, IOException {
        Sentence sentence = findById(id);
        sentence.setHandCount(sentence.getHandCount() + 1);
        updateEntity(sentence);

        // 记录系统数据日志（点赞数变化）
        sysDbLogBo.logOperation("UPDATE", "sentence", id, toJsonForLog(sentence));

        // 对作者进行奖励
        userBo.adjustCowDung(sentence.getAuthor(), 1, "例句得到了赞");

        Event event = new Event(EventType.HandSentenceEnglish, user, sentence);
        eventBo.createEntity(event);

        return new Result<>(true, null, sentence.getHandCount());
    }

    public Result<Integer> footSentence(String id, User user, String currWord)
            throws IllegalArgumentException, IllegalAccessException, InvalidMeaningFormatException, EmptySpellException,
            ParseException, IOException {
        Sentence sentence = findById(id);
        sentence.setFootCount(sentence.getFootCount() + 1);
        updateEntity(sentence);

        // 记录系统数据日志（踩数变化）
        sysDbLogBo.logOperation("UPDATE", "sentence", id, toJsonForLog(sentence));

        // 如果该例句被踩的次数比被赞的次数多3（或以上），删除该例句
        // if (sentence.getFootCount() - sentence.getHandCount() >= 3) {
        // deleteSentence(id, user, false);
        // }

        Event event = new Event(EventType.FootSentenceEnglsh, user, sentence);
        eventBo.createEntity(event);

        return new Result<>(true, null, sentence.getFootCount());
    }

    /**
     * 获取指定词书的例句，若dict为null，则表示获取词典的例句
     */
    public List<SentenceDto> getSentencesOfDict(String dictId) {
        // 通用词典现在是数据库中的实际记录，统一查询
        String sql = "SELECT s.id, s.english, s.english_digest, s.chinese, s.last_diy_update_time, s.the_type, s.producer, s.need_tts, s.foot_count, s.hand_count, s.author_id, s.meaning_item_id, s.word_meaning, s.create_time, s.update_time FROM sentence s LEFT JOIN meaning_item mi ON mi.id = s.meaning_item_id WHERE mi.dict_id = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);

        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            SentenceDto sentenceDto = new SentenceDto();
            sentenceDto.setId(rs.getString("id"));
            sentenceDto.setEnglish(rs.getString("english"));
            sentenceDto.setEnglishDigest(rs.getString("english_digest"));
            sentenceDto.setChinese(rs.getString("chinese"));
            sentenceDto.setLastDiyUpdateTime(rs.getTimestamp("last_diy_update_time"));
            sentenceDto.setTheType(rs.getString("the_type"));
            sentenceDto.setProducer(rs.getString("producer"));
            sentenceDto.setNeedTts(rs.getBoolean("need_tts"));
            sentenceDto.setFootCount(rs.getInt("foot_count"));
            sentenceDto.setHandCount(rs.getInt("hand_count"));
            sentenceDto.setAuthorId(rs.getString("author_id"));
            sentenceDto.setMeaningItemId(rs.getString("meaning_item_id"));
            sentenceDto.setWordMeaning(rs.getString("word_meaning"));
            sentenceDto.setCreateTime(rs.getTimestamp("create_time"));
            sentenceDto.setUpdateTime(rs.getTimestamp("update_time"));
            return sentenceDto;
        });
    }

    public Result<Void> deleteSentence(String id, String currWord, String userId)
            throws InvalidMeaningFormatException, EmptySpellException, ParseException, IOException {
        Sentence existing = findById(id);
        if (existing == null) {
            return Result.fail("例句不存在");
        }
        if (!(existing.getAuthor().equals(userBo.findById(userId)) || userBo.findById(userId).getIsInputor())) {
            return Result.fail("只有作者才能删除例句");
        }

        // 从数据库删除 - 例句的事件
        String sql = "DELETE FROM event WHERE sentence_id = :sentenceId";
        MapSqlParameterSource params = new MapSqlParameterSource("sentenceId", id);
        namedParameterJdbcTemplate.update(sql, params);

        // 从数据库删除 - 单词和例句的关联
        sql = "DELETE FROM word_sentence WHERE sentence_id = :sentenceId";
        namedParameterJdbcTemplate.update(sql, params);

        // 从数据库删除 - 例句翻译的事件
        sql = "DELETE FROM event WHERE sentence_chinese_id IN (SELECT id FROM sentence_chinese WHERE sentence_id = :sentenceId)";
        namedParameterJdbcTemplate.update(sql, params);

        // 从数据库删除 - 例句的翻译
        sql = "DELETE FROM sentence_chinese WHERE sentence_id = :sentenceId";
        namedParameterJdbcTemplate.update(sql, params);

        // 从数据库删除 - 例句本身
        sql = "DELETE FROM sentence WHERE id = :sentenceId";
        namedParameterJdbcTemplate.update(sql, params);

        // 记录系统数据日志（删除例句）
        sysDbLogBo.logOperation("DELETE", "sentence", id, "{}");

        // 从缓存清除
        sentenceCache.removeSentenceFromCache(id);
        return Result.success(null);
    }

    public Sentence createSentence(String english, String chinese, String wordId, int payCowdung, String currWord,
            String userId)
            throws IllegalAccessException, InvalidMeaningFormatException, EmptySpellException, ParseException,
            IOException {
        // 创建例句英文
        User user = userBo.findById(userId);
        Sentence sentence = new Sentence(english, user);
        sentence.setEnglishDigest(Util.makeSentenceDigest(english));
        sentence.setNeedTts(true);
        sentence.setTheType(Sentence.WAITTING_TTS);
        sentence.setHandCount(payCowdung);
        createEntity(sentence);

        // 记录系统数据日志（新增例句）
        sysDbLogBo.logOperation("INSERT", "sentence", sentence.getId(), toJsonForLog(sentence));

        // 把例句和单词关联
        WordSentenceId linkId = new WordSentenceId(wordId, sentence.getId());
        wordSentenceBo.createEntity(new WordSentence(linkId));

        // 付出魔法泡泡
        user.setCowDung(user.getCowDung() - payCowdung);
        userBo.updateEntity(user);

        return sentence;
    }

    /**
     * 将Sentence转为JSON字符串用于日志
     */
    private String toJsonForLog(Sentence sentence) {
        return JsonUtils.toJson(toDto(sentence));
    }

    public SentenceDto toDto(Sentence sentence) {
        SentenceDto dto = new SentenceDto();
        dto.setId(sentence.getId());
        dto.setEnglish(sentence.getEnglish());
        dto.setChinese(sentence.getChinese());
        dto.setEnglishDigest(sentence.getEnglishDigest());
        dto.setTheType(sentence.getTheType());
        dto.setFootCount(sentence.getFootCount());
        dto.setHandCount(sentence.getHandCount());
        dto.setAuthorId(sentence.getAuthor() != null ? sentence.getAuthor().getId() : null);
        dto.setMeaningItemId(sentence.getMeaningItem() != null ? sentence.getMeaningItem().getId() : null);
        dto.setWordMeaning(sentence.getWordMeaning());
        dto.setCreateTime(sentence.getCreateTime());
        dto.setUpdateTime(sentence.getUpdateTime());
        dto.setProducer(sentence.getSoundProducer());
        dto.setNeedTts(sentence.getNeedTts());
        dto.setLastDiyUpdateTime(sentence.getLastDiyUpdateTime());
        return dto;
    }

    // ============================================
    // 系统健康检查相关方法
    // ============================================

    /**
     * 查找缺少例句的释义项
     */
    public List<String> findMeaningsWithoutSentences(String dictId) {
        String sql = "SELECT mi.id " +
                "FROM meaning_item mi " +
                "WHERE mi.dict_id = :dictId " +
                "AND mi.id NOT IN (" +
                "    SELECT s.meaning_item_id " +
                "    FROM sentence s " +
                "    WHERE s.meaning_item_id = mi.id" +
                ")";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> rs.getString("id"));
    }
}
