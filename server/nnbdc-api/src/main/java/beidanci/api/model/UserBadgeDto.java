package beidanci.api.model;

import java.util.Date;

public class UserBadgeDto extends Dto {
    private String id;
    private String userId;
    private String badgeCode;
    private Integer obtainCount;
    private Integer starLevel;
    private Date unlockedAt;
    private Boolean isEquipped;
    private Boolean isViewed;

    public UserBadgeDto() {
    }

    public UserBadgeDto(String id, String userId, String badgeCode, Integer obtainCount, Integer starLevel, Date unlockedAt, Boolean isEquipped, Boolean isViewed) {
        this.id = id;
        this.userId = userId;
        this.badgeCode = badgeCode;
        this.obtainCount = obtainCount;
        this.starLevel = starLevel;
        this.unlockedAt = unlockedAt;
        this.isEquipped = isEquipped;
        this.isViewed = isViewed;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
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
}
