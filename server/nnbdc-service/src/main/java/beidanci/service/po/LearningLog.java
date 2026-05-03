package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

import beidanci.api.model.LearningLogDto;

@Entity
@Table(name = "learning_log")
public class LearningLog extends UuidPo {

    @Column(name = "user_id", nullable = false)
    private String userId;

    @Column(name = "word_id", nullable = false)
    private String wordId;

    @Column(name = "rating", nullable = false)
    private Integer rating;

    @Column(name = "stability", nullable = false)
    private Double stability;

    @Column(name = "difficulty", nullable = false)
    private Double difficulty;

    @Column(name = "elapsed_days", nullable = false)
    private Integer elapsedDays;

    @Column(name = "scheduled_days", nullable = false)
    private Integer scheduledDays;

    public LearningLog() {
    }

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

    public static LearningLog fromDto(LearningLogDto dto) {
        LearningLog log = new LearningLog();
        log.setId(dto.getId());
        log.setUserId(dto.getUserId());
        log.setWordId(dto.getWordId());
        log.setRating(dto.getRating());
        log.setStability(dto.getStability());
        log.setDifficulty(dto.getDifficulty());
        log.setElapsedDays(dto.getElapsedDays());
        log.setScheduledDays(dto.getScheduledDays());
        log.setCreateTime(dto.getCreateTime());
        log.setUpdateTime(dto.getUpdateTime() != null ? dto.getUpdateTime() : dto.getCreateTime());
        return log;
    }
}
