package beidanci.api.model;

import java.util.Date;

public class LearningWordDto {
    private String userId;
    private String wordId;
    private Date addTime;
    private Integer addDay;
    private Date lastLearningDate;
    private Boolean isTodayNewWord;
    private Integer learningOrder;
    private Integer learnedTimes;
    private Integer todayLearnedTimes;
    private Integer batchId;
    private Double stability;
    private Double difficulty;
    private Integer elapsedDays;
    private Integer scheduledDays;
    private Integer reps;
    private Integer lapses;
    private Integer state;
    private Date createTime;
    private Date updateTime;

    public LearningWordDto() {
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    public Date getAddTime() {
        return addTime;
    }

    public void setAddTime(Date addTime) {
        this.addTime = addTime;
    }

    public Integer getAddDay() {
        return addDay;
    }

    public void setAddDay(Integer addDay) {
        this.addDay = addDay;
    }


    public Date getLastLearningDate() {
        return lastLearningDate;
    }

    public void setLastLearningDate(Date lastLearningDate) {
        this.lastLearningDate = lastLearningDate;
    }


    public Integer getLearningOrder() {
        return learningOrder;
    }

    public void setLearningOrder(Integer learningOrder) {
        this.learningOrder = learningOrder;
    }

    public Integer getLearnedTimes() {
        return learnedTimes;
    }

    public void setLearnedTimes(Integer learnedTimes) {
        this.learnedTimes = learnedTimes;
    }

    public Integer getTodayLearnedTimes() {
        return todayLearnedTimes;
    }

    public void setTodayLearnedTimes(Integer todayLearnedTimes) {
        this.todayLearnedTimes = todayLearnedTimes;
    }

    public Date getCreateTime() {
        return createTime;
    }

    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }

    public Date getUpdateTime() {
        return updateTime;
    }

    public void setUpdateTime(Date updateTime) {
        this.updateTime = updateTime;
    }

    public Boolean getIsTodayNewWord() {
        return isTodayNewWord;
    }

    public void setIsTodayNewWord(Boolean isTodayNewWord) {
        this.isTodayNewWord = isTodayNewWord;
    }

    public Integer getBatchId() {
        return batchId;
    }

    public void setBatchId(Integer batchId) {
        this.batchId = batchId;
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

}
