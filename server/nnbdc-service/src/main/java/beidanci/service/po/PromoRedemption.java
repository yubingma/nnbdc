package beidanci.service.po;

import java.util.Date;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

@Entity
@Table(name = "promo_redemption")
public class PromoRedemption extends UuidPo {

    @Column(name = "user_id", length = 32, nullable = false)
    private String userId;

    @Column(name = "activity_id", length = 32, nullable = false)
    private String activityId;

    @Column(name = "redeem_time", nullable = false)
    private Date redeemTime;

    public PromoRedemption() {
    }

    public PromoRedemption(String id, String userId, String activityId, Date redeemTime) {
        this.id = id;
        this.userId = userId;
        this.activityId = activityId;
        this.redeemTime = redeemTime;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getActivityId() {
        return activityId;
    }

    public void setActivityId(String activityId) {
        this.activityId = activityId;
    }

    public Date getRedeemTime() {
        return redeemTime;
    }

    public void setRedeemTime(Date redeemTime) {
        this.redeemTime = redeemTime;
    }
}
