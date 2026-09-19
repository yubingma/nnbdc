package beidanci.api.model;

import java.util.Date;

public class CigenWordLinkDto extends Dto {
    private String cigenId;
    private String wordId;
    private String theExplain;
    private Date createTime;
    private Date updateTime;

    public CigenWordLinkDto() {
    }

    public CigenWordLinkDto(String cigenId, String wordId, String theExplain, Date createTime, Date updateTime) {
        this.cigenId = cigenId;
        this.wordId = wordId;
        this.theExplain = theExplain;
        this.createTime = createTime;
        this.updateTime = updateTime;
    }

    public String getCigenId() {
        return cigenId;
    }

    public void setCigenId(String cigenId) {
        this.cigenId = cigenId;
    }

    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    public String getTheExplain() {
        return theExplain;
    }

    public void setTheExplain(String theExplain) {
        this.theExplain = theExplain;
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
