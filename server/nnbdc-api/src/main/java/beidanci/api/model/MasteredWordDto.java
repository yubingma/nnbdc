package beidanci.api.model;

import java.util.Date;

public class MasteredWordDto {
    private String userId;
    private String wordId;
    private Date masterAtTime;
    private Date createTime;
    private Date updateTime;

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

    public Date getMasterAtTime() {
        return masterAtTime;
    }

    public void setMasterAtTime(Date masterAtTime) {
        this.masterAtTime = masterAtTime;
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
}
