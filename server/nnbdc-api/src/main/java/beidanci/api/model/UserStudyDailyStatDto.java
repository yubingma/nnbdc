package beidanci.api.model;

import java.util.Date;

/**
 * 每日学习统计DTO
 */
public class UserStudyDailyStatDto implements Dto {

    private String userId;
    private Date date;
    private Integer studySeconds;
    private Integer reviewCount;
    private String dayStatus;

    public UserStudyDailyStatDto() {
    }

    public UserStudyDailyStatDto(String userId, Date date, Integer studySeconds, Integer reviewCount, String dayStatus) {
        this.userId = userId;
        this.date = date;
        this.studySeconds = studySeconds;
        this.reviewCount = reviewCount;
        this.dayStatus = dayStatus;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public Date getDate() {
        return date;
    }

    public void setDate(Date date) {
        this.date = date;
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

    private Date createTime;
    private Date updateTime;

    public Date getCreateTime() {
        return createTime == null ? new Date(0) : createTime;
    }

    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }

    public Date getUpdateTime() {
        return updateTime == null ? (createTime == null ? new Date(0) : createTime) : updateTime;
    }

    public void setUpdateTime(Date updateTime) {
        this.updateTime = updateTime;
    }
}
