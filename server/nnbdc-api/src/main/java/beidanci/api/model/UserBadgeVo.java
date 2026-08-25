package beidanci.api.model;

import java.util.Date;

public class UserBadgeVo extends UuidVo {
    private String userId;
    private String badgeCode;
    private BadgeVo badge;
    private Integer obtainCount;
    private Integer starLevel;
    private Date unlockedAt;
    private Boolean isEquipped;
    private Boolean isViewed;
    private Boolean isUnlocked;
    private Integer progressCurrent;
    private Integer progressTarget;
    private Double progressPercent;

    public UserBadgeVo() {
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getBadgeCode() {
        return badgeCode;
    }

    public void setBadgeCode(String badgeCode) {
        this.badgeCode = badgeCode;
    }

    public BadgeVo getBadge() {
        return badge;
    }

    public void setBadge(BadgeVo badge) {
        this.badge = badge;
    }

    public Integer getObtainCount() {
        return obtainCount;
    }

    public void setObtainCount(Integer obtainCount) {
        this.obtainCount = obtainCount;
    }

    public Integer getStarLevel() {
        return starLevel;
    }

    public void setStarLevel(Integer starLevel) {
        this.starLevel = starLevel;
    }

    public Date getUnlockedAt() {
        return unlockedAt;
    }

    public void setUnlockedAt(Date unlockedAt) {
        this.unlockedAt = unlockedAt;
    }

    public Boolean getIsEquipped() {
        return isEquipped;
    }

    public void setIsEquipped(Boolean isEquipped) {
        this.isEquipped = isEquipped;
    }

    public Boolean getIsViewed() {
        return isViewed;
    }

    public void setIsViewed(Boolean isViewed) {
        this.isViewed = isViewed;
    }

    public Boolean getIsUnlocked() {
        return isUnlocked;
    }

    public void setIsUnlocked(Boolean isUnlocked) {
        this.isUnlocked = isUnlocked;
    }

    public Integer getProgressCurrent() {
        return progressCurrent;
    }

    public void setProgressCurrent(Integer progressCurrent) {
        this.progressCurrent = progressCurrent;
    }

    public Integer getProgressTarget() {
        return progressTarget;
    }

    public void setProgressTarget(Integer progressTarget) {
        this.progressTarget = progressTarget;
    }

    public Double getProgressPercent() {
        return progressPercent;
    }

    public void setProgressPercent(Double progressPercent) {
        this.progressPercent = progressPercent;
    }
}
