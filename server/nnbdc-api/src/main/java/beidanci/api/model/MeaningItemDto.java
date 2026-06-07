package beidanci.api.model;

import java.util.Date;

public class MeaningItemDto extends Dto implements Ownerable {
    private String id;
    private String ciXing;
    private String meaning;
    private int popularity;
    private Integer popularityPercent;
    private boolean isUpdating;
    private Date updatingStartAt;

    /** word id */
    private String wordId;

    private String dictId;
    private String ownerId;

    public String getOwnerId() {
        return ownerId;
    }

    public void setOwnerId(String ownerId) {
        this.ownerId = ownerId;
    }

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

    public Integer getPopularityPercent() {
        return popularityPercent;
    }

    public void setPopularityPercent(Integer popularityPercent) {
        this.popularityPercent = popularityPercent;
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
