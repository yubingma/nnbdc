package beidanci.api.model;

import java.util.Date;

public class LearningDictDto {
    private String dictId;
    private String userId;
    private Integer currentWordSeq;
    private Boolean isPrivileged;
    private String currentWord;
    private Boolean fetchMastered;
    private Date createTime;
    private Date updateTime;

    public LearningDictDto() {
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

    public String getDictId() {
        return dictId;
    }

    public void setDictId(String dictId) {
        this.dictId = dictId;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public Integer getCurrentWordSeq() {
        return currentWordSeq;
    }

    public void setCurrentWordSeq(Integer currentWordSeq) {
        this.currentWordSeq = currentWordSeq;
    }


    public String getCurrentWord() {
        return currentWord;
    }

    public void setCurrentWord(String currentWord) {
        this.currentWord = currentWord;
    }

    public Boolean getIsPrivileged() {
        return isPrivileged;
    }

    public void setIsPrivileged(Boolean isPrivileged) {
        this.isPrivileged = isPrivileged;
    }

    public Boolean getFetchMastered() {
        return fetchMastered;
    }

    public void setFetchMastered(Boolean fetchMastered) {
        this.fetchMastered = fetchMastered;
    }


}
