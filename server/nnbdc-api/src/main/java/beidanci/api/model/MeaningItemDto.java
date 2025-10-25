package beidanci.api.model;

import java.util.Date;

public class MeaningItemDto implements Dto {
    private String id;
    private Date createTime;
    private Date updateTime;
    private String ciXing;
    private String meaning;
    private int popularity;
    private boolean isUpdating;
    private Date updatingStartAt;

    /** word id */
    private String wordId;

    private String dictId;

    public boolean isUpdating() {
        return isUpdating;
    }

    public void setUpdating(boolean isUpdating) {
        this.isUpdating = isUpdating;
    }

    public Date getUpdatingStartAt() {
        return updatingStartAt;
    }

    public void setUpdatingStartAt(Date updatingStartAt) {
        this.updatingStartAt = updatingStartAt;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
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

    public String getCiXing() {
        return ciXing;
    }

    public void setCiXing(String ciXing) {
        this.ciXing = ciXing;
    }

    public String getMeaning() {
        return meaning;
    }

    public void setMeaning(String meaning) {
        this.meaning = meaning;
    }

    public int getPopularity() {
        return popularity;
    }

    public void setPopularity(int popularity) {
        this.popularity = popularity;
    }

    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    public String getDictId() {
        return dictId;
    }

    public void setDictId(String dictId) {
        this.dictId = dictId;
    }
}
