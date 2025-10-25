package beidanci.api.model;

import java.util.Date;

public class SentenceDto implements Dto {
    private String english;
    private String id;
    private String chinese;
    private String wordMeaning;
    private String englishDigest;
    private Date lastDiyUpdateTime;
    private String theType;
    private Integer footCount;
    private Integer handCount;
    private String producer;
    private Boolean needTts;
    private String meaningItemId;
    private Date createTime;
    private Date updateTime;

    /** author id */
    private String authorId;

    public String getProducer() {
        return producer;
    }

    public void setProducer(String producer) {
        this.producer = producer;
    }

    public Boolean getNeedTts() {
        return needTts;
    }

    public void setNeedTts(Boolean needTts) {
        this.needTts = needTts;
    }

    public String getMeaningItemId() {
        return meaningItemId;
    }

    public void setMeaningItemId(String meaningItemId) {
        this.meaningItemId = meaningItemId;
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

    public String getEnglish() {
        return english;
    }

    public void setEnglish(String english) {
        this.english = english;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getChinese() {
        return chinese;
    }

    public void setChinese(String chinese) {
        this.chinese = chinese;
    }

    public String getWordMeaning() {
        return wordMeaning;
    }

    public void setWordMeaning(String wordMeaning) {
        this.wordMeaning = wordMeaning;
    }

    public String getEnglishDigest() {
        return englishDigest;
    }

    public void setEnglishDigest(String englishDigest) {
        this.englishDigest = englishDigest;
    }

    public String getTheType() {
        return theType;
    }

    public void setTheType(String theType) {
        this.theType = theType;
    }

    public Integer getFootCount() {
        return footCount;
    }

    public void setFootCount(Integer footCount) {
        this.footCount = footCount;
    }

    public Integer getHandCount() {
        return handCount;
    }

    public void setHandCount(Integer handCount) {
        this.handCount = handCount;
    }

    public String getAuthorId() {
        return authorId;
    }

    public void setAuthorId(String authorId) {
        this.authorId = authorId;
    }

    public Date getLastDiyUpdateTime() {
        return lastDiyUpdateTime;
    }

    public void setLastDiyUpdateTime(Date lastDiyUpdateTime) {
        this.lastDiyUpdateTime = lastDiyUpdateTime;
    }

}
