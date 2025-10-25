package beidanci.api.model;

import java.util.Date;

public class LearningWordDto {
    private String userId;
    private String wordId;
    private Date addTime;
    private Integer addDay;
    private Integer lifeValue;
    private Date lastLearningDate;
    private Boolean isTodayNewWord;
    private Integer learningOrder;
    private Integer learnedTimes;
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

    public Integer getLifeValue() {
        return lifeValue;
    }

    public void setLifeValue(Integer lifeValue) {
        this.lifeValue = lifeValue;
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

}
