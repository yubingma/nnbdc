package beidanci.service.po;

import java.io.IOException;
import java.sql.Timestamp;
import java.util.Date;
import java.util.Objects;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Index;
import javax.persistence.Table;

import beidanci.api.model.LearningWordDto;
import beidanci.api.model.WordVo;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.store.WordCache;

@Entity
@Table(name = "learning_word", indexes = {@Index(name = "idx_userid", columnList = "user_id")})
public class LearningWord extends Po {

    @Id
    private LearningWordId id;

    @Column(name = "user_id")
    private User user;

    @Column(name = "add_time", nullable = false)
    private Date addTime;

    @Column(name = "add_day", nullable = false)
    private Integer addDay;


    @Column(name = "last_learning_date")
    private Date lastLearningDate;

    @Column(name = "learning_order")
    private Integer learningOrder;

    @Column(name = "batch_id")
    private Integer batchId;

    /**
     * 已学习次数，一个单词完成一天的学习，这个值增加的值一般大于1（因为用户一般会选择多个学习步骤）
     */
    @Column(name = "learned_times", nullable = false)
    private Integer learnedTimes;

    @Column(name = "today_learned_times", nullable = false)
    private Integer todayLearnedTimes = 0;

    @Column(name = "stability")
    private Double stability;

    @Column(name = "difficulty")
    private Double difficulty;

    @Column(name = "elapsed_days")
    private Integer elapsedDays;

    @Column(name = "scheduled_days")
    private Integer scheduledDays;

    @Column(name = "reps")
    private Integer reps;

    @Column(name = "lapses")
    private Integer lapses;

    /**
     * FSRS 状态: 0: New (新词), 1: Learning (学习中), 2: Review (复习), 3: Relearning (重学)
     */
    @Column(name = "state")
    private Integer state;


    /**
     * 是否是新词。本属性仅对今日学习中的单词有意义。
     * 为本属性赋值的逻辑是：
     * 当从学习中单词列表选择今日单词时，判断所选单词的已学习次数，如果已学习次数为0，则本属性赋值为true
     */
    @Column(name = "is_today_new_word", nullable = false)
    private Boolean isTodayNewWord;

    /**
     * default constructor
     */
    public LearningWord() {
    }

    /**
     * minimal constructor
     */
    public LearningWord(LearningWordId id, User user, Timestamp addTime, Integer addDay) {
        this.id = id;
        this.user = user;
        this.addTime = addTime;
        this.addDay = addDay;
        this.learnedTimes = 0;
        this.todayLearnedTimes = 0;
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

    public Integer getBatchId() {
        return batchId;
    }

    public void setBatchId(Integer batchId) {
        this.batchId = batchId;
    }

    public Integer getTodayLearnedTimes() {
        return todayLearnedTimes;
    }

    public void setTodayLearnedTimes(Integer todayLearnedTimes) {
        this.todayLearnedTimes = todayLearnedTimes;
    }

    public Double getStability() {
        return stability;
    }

    public void setStability(Double stability) {
        this.stability = stability;
    }

    public Double getDifficulty() {
        return difficulty;
    }

    public void setDifficulty(Double difficulty) {
        this.difficulty = difficulty;
    }

    public Integer getElapsedDays() {
        return elapsedDays;
    }

    public void setElapsedDays(Integer elapsedDays) {
        this.elapsedDays = elapsedDays;
    }

    public Integer getScheduledDays() {
        return scheduledDays;
    }

    public void setScheduledDays(Integer scheduledDays) {
        this.scheduledDays = scheduledDays;
    }

    public Integer getReps() {
        return reps;
    }

    public void setReps(Integer reps) {
        this.reps = reps;
    }

    public Integer getLapses() {
        return lapses;
    }

    public void setLapses(Integer lapses) {
        this.lapses = lapses;
    }

    public Integer getState() {
        return state;
    }

    public void setState(Integer state) {
        this.state = state;
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
        learningWord.setLastLearningDate(dto.getLastLearningDate());
        learningWord.setAddTime(dto.getAddTime());
        learningWord.setAddDay(dto.getAddDay());
        learningWord.setLearningOrder(dto.getLearningOrder());
        learningWord.setLearnedTimes(dto.getLearnedTimes());
        Integer todayLearnedTimes = dto.getTodayLearnedTimes();
        learningWord.setTodayLearnedTimes(todayLearnedTimes != null ? todayLearnedTimes : 0);
        learningWord.setIsTodayNewWord(dto.getIsTodayNewWord());
        Integer batchId = dto.getBatchId();
        learningWord.setBatchId(batchId != null ? batchId : 0);
        if (dto.getCreateTime() != null) {
            learningWord.setCreateTime(dto.getCreateTime());
        }
        if (dto.getUpdateTime() != null) {
            learningWord.setUpdateTime(dto.getUpdateTime());
        } else {
            learningWord.setUpdateTime(dto.getCreateTime());
        }
        learningWord.setStability(dto.getStability());
        learningWord.setDifficulty(dto.getDifficulty());
        learningWord.setElapsedDays(dto.getElapsedDays());
        learningWord.setScheduledDays(dto.getScheduledDays());
        learningWord.setReps(dto.getReps());
        learningWord.setLapses(dto.getLapses());
        learningWord.setState(dto.getState());
        return learningWord;
    }

    public LearningWordDto swallowToDto() {
        LearningWordDto dto = new LearningWordDto();
        dto.setUserId(id.getUserId());
        dto.setWordId(id.getWordId());
        dto.setAddTime(addTime);
        dto.setAddDay(addDay);
        dto.setLastLearningDate(lastLearningDate);
        dto.setLearningOrder(learningOrder);
        dto.setLearnedTimes(learnedTimes);
        dto.setTodayLearnedTimes(todayLearnedTimes);
        dto.setIsTodayNewWord(isTodayNewWord);
        dto.setBatchId(batchId);
        dto.setStability(stability);
        dto.setDifficulty(difficulty);
        dto.setElapsedDays(elapsedDays);
        dto.setScheduledDays(scheduledDays);
        dto.setReps(reps);
        dto.setLapses(lapses);
        dto.setState(state);
        dto.setCreateTime(createTime);
        dto.setUpdateTime(updateTime);
        return dto;
    }
}
