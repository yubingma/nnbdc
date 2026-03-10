package beidanci.api.model;

import java.util.Date;

public class LearningLogDto {
    private String id;
    private String userId;
    private String wordId;
    private Integer rating;
    private Double stability;
    private Double difficulty;
    private Integer elapsedDays;
    private Integer scheduledDays;
    private Date createTime;
    private Date updateTime;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getWordId() { return wordId; }
    public void setWordId(String wordId) { this.wordId = wordId; }

    public Integer getRating() { return rating; }
    public void setRating(Integer rating) { this.rating = rating; }

    public Double getStability() { return stability; }
    public void setStability(Double stability) { this.stability = stability; }

    public Double getDifficulty() { return difficulty; }
    public void setDifficulty(Double difficulty) { this.difficulty = difficulty; }

    public Integer getElapsedDays() { return elapsedDays; }
    public void setElapsedDays(Integer elapsedDays) { this.elapsedDays = elapsedDays; }

    public Integer getScheduledDays() { return scheduledDays; }
    public void setScheduledDays(Integer scheduledDays) { this.scheduledDays = scheduledDays; }

    public Date getCreateTime() { return createTime; }
    public void setCreateTime(Date createTime) { this.createTime = createTime; }

    public Date getUpdateTime() { return updateTime; }
    public void setUpdateTime(Date updateTime) { this.updateTime = updateTime; }
}
