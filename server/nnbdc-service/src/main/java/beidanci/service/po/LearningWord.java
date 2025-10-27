package beidanci.service.po;

import java.io.IOException;
import java.sql.Timestamp;
import java.util.Date;
import java.util.Objects;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Index;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

import beidanci.api.model.LearningWordDto;
import beidanci.api.model.WordVo;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.store.WordCache;

@Entity
@Table(name = "learning_word", indexes = {@Index(name = "idx_userid", columnList = "userId")})
public class LearningWord extends Po {
    public static final Integer NEW_LEARNING_WORD_LIFE_VALUE = 5;

    @Id
    private LearningWordId id;

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false, updatable = false, insertable = false)
    private User user;

    @Column(name = "addTime", nullable = false)
    private Date addTime;

    @Column(name = "addDay", nullable = false)
    private Integer addDay;

    @Column(name = "lifeValue", nullable = false)
    private Integer lifeValue;

    @Column(name = "lastLearningDate")
    private Date lastLearningDate;

    @Column(name = "learningOrder")
    private Integer learningOrder;

    /**
     * 已学习次数，一个单词完成一天的学习，这个值增加的值一般大于1（因为用户一般会选择多个学习步骤）
     */
    @Column(name = "learnedTimes", nullable = false)
    private Integer learnedTimes;


    /**
     * 是否是新词。本属性仅对今日学习中的单词有意义。
     * 为本属性赋值的逻辑是：
     * 当从学习中单词列表选择今日单词时，判断所选单词的已学习次数，如果已学习次数为0，则本属性赋值为true
     */
    @Column(name = "isTodayNewWord", nullable = false)
    private Boolean isTodayNewWord;

    /**
     * default constructor
     */
    public LearningWord() {
    }

    /**
     * minimal constructor
     */
    public LearningWord(LearningWordId id, User user, Timestamp addTime, Integer addDay, Integer lifeValue) {
        this.id = id;
        this.user = user;
        this.addTime = addTime;
        this.addDay = addDay;
        this.lifeValue = lifeValue;
        this.learnedTimes = 0;
        this.isTodayNewWord = false;
    }

    public LearningWord(User user) {
        this.user = user;
    }

    public Integer getLearnedTimes() {
        return learnedTimes;
    }

    public void setLearnedTimes(Integer learnedTimes) {
        this.learnedTimes = learnedTimes;
    }

    public Boolean getIsTodayNewWord() {
        return isTodayNewWord;
    }

    public void setIsTodayNewWord(Boolean isTodayNewWord) {
        this.isTodayNewWord = isTodayNewWord;
    }


    public LearningWordId getId() {
        return this.id;
    }

    public void setId(LearningWordId id) {
        this.id = id;
    }

    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Date getAddTime() {
        return this.addTime;
    }

    public void setAddTime(Date addTime) {
        this.addTime = addTime;
    }

    public Integer getAddDay() {
        return this.addDay;
    }

    public void setAddDay(Integer addDay) {
        this.addDay = addDay;
    }

    public Integer getLifeValue() {
        return this.lifeValue;
    }

    public void setLifeValue(Integer lifeValue) {
        this.lifeValue = lifeValue;
    }

    public Date getLastLearningDate() {
        return this.lastLearningDate;
    }

    public void setLastLearningDate(Date lastLearningDate) {
        this.lastLearningDate = lastLearningDate;
    }

    public Integer getLearningOrder() {
        return this.learningOrder;
    }

    public void setLearningOrder(Integer learningOrder) {
        this.learningOrder = learningOrder;
    }

    public WordVo getWord(WordCache wordCache, String[] excludeFields) throws IOException, ParseException, InvalidMeaningFormatException, EmptySpellException {
        return wordCache.getWordById(id.getWordId(), excludeFields);
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        LearningWord that = (LearningWord) o;
        return id.equals(that.id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id);
    }

    public static LearningWord fromDto(LearningWordDto dto) {
        LearningWordId id = new LearningWordId(dto.getUserId(), dto.getWordId());
        LearningWord learningWord = new LearningWord();
        learningWord.setId(id);
        learningWord.setLifeValue(dto.getLifeValue());
        learningWord.setLastLearningDate(dto.getLastLearningDate());
        learningWord.setAddTime(dto.getAddTime());
        learningWord.setAddDay(dto.getAddDay());
        learningWord.setLearningOrder(dto.getLearningOrder());
        learningWord.setLearnedTimes(dto.getLearnedTimes());
        learningWord.setIsTodayNewWord(dto.getIsTodayNewWord());
        if (dto.getCreateTime() != null) {
            learningWord.setCreateTime(dto.getCreateTime());
        }
        if (dto.getUpdateTime() != null) {
            learningWord.setUpdateTime(dto.getUpdateTime());
        }
        return learningWord;
    }
}
