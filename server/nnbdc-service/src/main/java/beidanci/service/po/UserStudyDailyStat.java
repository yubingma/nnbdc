package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Table;

@Entity
@Table(name = "user_study_daily_stat")
public class UserStudyDailyStat extends Po {

    @Id
    private UserStudyDailyStatId id;

    @Column(name = "study_seconds")
    private Integer studySeconds;

    @Column(name = "review_count")
    private Integer reviewCount;

    @Column(name = "day_status")
    private String dayStatus;

    public UserStudyDailyStat() {
    }

    public UserStudyDailyStat(UserStudyDailyStatId id, Integer studySeconds, Integer reviewCount, String dayStatus) {
        this.id = id;
        this.studySeconds = studySeconds;
        this.reviewCount = reviewCount;
        this.dayStatus = dayStatus;
    }

    public UserStudyDailyStatId getId() {
        return id;
    }

    public void setId(UserStudyDailyStatId id) {
        this.id = id;
    }

    public Integer getStudySeconds() {
        return studySeconds;
    }

    public void setStudySeconds(Integer studySeconds) {
        this.studySeconds = studySeconds;
    }

    public Integer getReviewCount() {
        return reviewCount;
    }

    public void setReviewCount(Integer reviewCount) {
        this.reviewCount = reviewCount;
    }

    public String getDayStatus() {
        return dayStatus;
    }

    public void setDayStatus(String dayStatus) {
        this.dayStatus = dayStatus;
    }
}
