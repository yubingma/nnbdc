package beidanci.service.po;

import java.util.Date;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;
import javax.persistence.UniqueConstraint;

@Entity
@Table(name = "user_badge", uniqueConstraints = {
    @UniqueConstraint(columnNames = {"user_id", "badge_code"})
})
public class UserBadge extends UuidPo {

    @Column(name = "user_id", length = 32, nullable = false)
    private String userId;

    @Column(name = "badge_code", length = 50, nullable = false)
    private String badgeCode;

    @Column(name = "obtain_count", nullable = false)
    private Integer obtainCount = 1;

    @Column(name = "star_level", nullable = false)
    private Integer starLevel = 1;

    @Column(name = "unlocked_at", nullable = false)
    private Date unlockedAt;

    @Column(name = "is_equipped", nullable = false)
    private Boolean isEquipped = false;

    @Column(name = "is_viewed", nullable = false)
    private Boolean isViewed = false;

    public UserBadge() {
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
