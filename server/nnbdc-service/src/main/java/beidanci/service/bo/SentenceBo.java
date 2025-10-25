package beidanci.service.bo;
import java.io.IOException;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.List;

import javax.annotation.PostConstruct;

import org.hibernate.query.Query;
import org.springframework.beans.factory.annotation.Autowired;
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
    SysDbLogBo sysDbLogBo;

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
        String sql = "select s.id, s.english, s.englishDigest, s.chinese, s.lastDiyUpdateTime, s.theType, s.producer, s.needTts, s.footCount, s.handCount, s.authorId, s.meaningItemId, s.wordMeaning, s.createTime, s.updateTime from sentence s left join meaning_item mi on mi.id = s.meaningItemId where mi.dictId = :dictId";
        Query<?> query = getSession().createNativeQuery(sql);
        List<?> results = query.setParameter("dictId", dictId).list();

        List<SentenceDto> sentenceDtos = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            SentenceDto sentenceDto = new SentenceDto();
            sentenceDto.setId((String) tuple[0]);
            sentenceDto.setEnglish((String) tuple[1]);
            sentenceDto.setEnglishDigest((String) tuple[2]);
            sentenceDto.setChinese((String) tuple[3]);
            sentenceDto.setLastDiyUpdateTime((Timestamp) tuple[4]);
            sentenceDto.setTheType((String) tuple[5]);
            sentenceDto.setProducer((String) tuple[6]);
            sentenceDto.setNeedTts((Boolean) tuple[7]);
            sentenceDto.setFootCount((Integer) tuple[8]);
            sentenceDto.setHandCount((Integer) tuple[9]);
            sentenceDto.setAuthorId((String) tuple[10]);
            sentenceDto.setMeaningItemId((String) tuple[11]);
            sentenceDto.setWordMeaning((String) tuple[12]);
            sentenceDto.setCreateTime((Timestamp) tuple[13]);
            sentenceDto.setUpdateTime((Timestamp) tuple[14]);
            sentenceDtos.add(sentenceDto);
        }
        return sentenceDtos;
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
        String hql = "delete from Event where sentence.id=:sentenceId";
        Query<Long> query = getSession().createQuery(hql, Long.class);
        query.setParameter("sentenceId", id);
        query.executeUpdate();

        // 从数据库删除 - 单词和例句的关联
        hql = "delete from WordSentence where id.sentenceId=:sentenceId";
        query = getSession().createQuery(hql, Long.class);
        query.setParameter("sentenceId", id);
        query.executeUpdate();

        // 从数据库删除 - 例句翻译的事件
        hql = "delete from Event where sentenceChinese.id in (select id from SentenceChinese where sentence.id=:sentenceId)";
        query = getSession().createQuery(hql, Long.class);
        query.setParameter("sentenceId", id);
        query.executeUpdate();

        // 从数据库删除 - 例句的翻译
        hql = "delete from SentenceChinese where sentence.id=:sentenceId";
        query = getSession().createQuery(hql, Long.class);
        query.setParameter("sentenceId", id);
        query.executeUpdate();

        // 从数据库删除 - 例句本身
        hql = "delete from Sentence where id=:sentenceId";
        query = getSession().createQuery(hql, Long.class);
        query.setParameter("sentenceId", id);
        query.executeUpdate();

        // 记录系统数据日志（删除例句）
        sysDbLogBo.logOperation("DELETE", "sentence", id, "{}");

        // 从缓存清除
        sentenceCache.removeSentenceFromCache(id);
        return Result.success(null);
    }

    public Sentence createSentence(String english, String chinese, String wordId, int payCowdung, String currWord, String userId)
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

                    // 付出泡泡糖
        user.setCowDung(user.getCowDung() - payCowdung);
        userBo.updateEntity(user);

        return sentence;
    }

    /**
     * 将Sentence转为JSON字符串用于日志
     */
    private String toJsonForLog(Sentence sentence) {
        try {
            // 用于格式化日期为ISO-8601格式
            java.text.SimpleDateFormat isoFormat = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
            isoFormat.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
            
            String createTimeStr = sentence.getCreateTime() != null ? isoFormat.format(sentence.getCreateTime()) : "";
            String updateTimeStr = sentence.getUpdateTime() != null ? isoFormat.format(sentence.getUpdateTime()) : "";
            
            return String.format(
                "{\"id\":\"%s\",\"english\":\"%s\",\"chinese\":\"%s\",\"englishDigest\":\"%s\",\"theType\":\"%s\",\"handCount\":%d,\"footCount\":%d,\"author\":\"%s\",\"meaningItemId\":\"%s\",\"wordMeaning\":\"%s\",\"createTime\":\"%s\",\"updateTime\":\"%s\"}",
                sentence.getId(),
                sentence.getEnglish() != null ? sentence.getEnglish().replace("\"", "\\\"") : "",
                sentence.getChinese() != null ? sentence.getChinese().replace("\"", "\\\"") : "",
                sentence.getEnglishDigest() != null ? sentence.getEnglishDigest() : "",
                sentence.getTheType() != null ? sentence.getTheType() : "",
                sentence.getHandCount(),
                sentence.getFootCount(),
                sentence.getAuthor() != null ? sentence.getAuthor().getId() : "",
                sentence.getMeaningItem() != null ? sentence.getMeaningItem().getId() : "",
                sentence.getWordMeaning() != null ? sentence.getWordMeaning().replace("\"", "\\\"") : "",
                createTimeStr,
                updateTimeStr
            );
        } catch (Exception e) {
            return "{}";
        }
    }
}
