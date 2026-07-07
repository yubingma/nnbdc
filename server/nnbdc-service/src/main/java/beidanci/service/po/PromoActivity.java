package beidanci.service.po;

import java.util.Date;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

@Entity
@Table(name = "promo_activity")
public class PromoActivity extends UuidPo {

    @Column(name = "activity_code", length = 50, unique = true, nullable = false)
    private String activityCode;

    @Column(name = "name", length = 100, nullable = false)
    private String name;

    @Column(name = "duration", length = 50)
    private String duration;

    @Column(name = "start_time")
    private Date startTime;

    @Column(name = "end_time")
    private Date endTime;

    @Column(name = "max_redemptions")
    private Integer maxRedemptions;

    @Column(name = "redemption_count", nullable = false)
    private Integer redemptionCount = 0;

    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;

    public PromoActivity() {
    }

    public PromoActivity(String id, String activityCode, String name, String duration, Date startTime, Date endTime, Integer maxRedemptions) {
        this.id = id;
        this.activityCode = activityCode;
        this.name = name;
        this.duration = duration;
        this.startTime = startTime;
        this.endTime = endTime;
        this.maxRedemptions = maxRedemptions;
        this.redemptionCount = 0;
        this.isActive = true;
    }

    public String getActivityCode() {
        return activityCode;
    }

    public void setActivityCode(String activityCode) {
        this.activityCode = activityCode;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getDuration() {
        return duration;
    }

    public void setDuration(String duration) {
        this.duration = duration;
    }

    public Date getStartTime() {
        return startTime;
    }

    public void setStartTime(Date startTime) {
        this.startTime = startTime;
    }

    public Date getEndTime() {
        return endTime;
    }

    public void setEndTime(Date endTime) {
        this.endTime = endTime;
    }

    public Integer getMaxRedemptions() {
        return maxRedemptions;
    }

    public void setMaxRedemptions(Integer maxRedemptions) {
        this.maxRedemptions = maxRedemptions;
    }

    public Integer getRedemptionCount() {
        return redemptionCount;
    }

    public void setRedemptionCount(Integer redemptionCount) {
        this.redemptionCount = redemptionCount;
    }

    public Boolean getIsActive() {
        return isActive;
    }

    public void setIsActive(Boolean isActive) {
        this.isActive = isActive;
    }
}
