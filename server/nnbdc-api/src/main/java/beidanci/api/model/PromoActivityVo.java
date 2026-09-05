package beidanci.api.model;

import java.util.Date;

public class PromoActivityVo extends UuidVo {
    private String activityCode;
    private String name;
    private String duration;
    private Date startTime;
    private Date endTime;
    private Integer maxRedemptions;
    private Integer redemptionCount;
    private Boolean isActive;
    private Boolean showCodeToUser;
    private Boolean showRedeemUi;
    private String replyMessage;

    public PromoActivityVo() {
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

    public Boolean getShowCodeToUser() {
        return showCodeToUser;
    }

    public void setShowCodeToUser(Boolean showCodeToUser) {
        this.showCodeToUser = showCodeToUser;
    }

    public Boolean getShowRedeemUi() {
        return showRedeemUi;
    }

    public void setShowRedeemUi(Boolean showRedeemUi) {
        this.showRedeemUi = showRedeemUi;
    }

    public String getReplyMessage() {
        return replyMessage;
    }

    public void setReplyMessage(String replyMessage) {
        this.replyMessage = replyMessage;
    }
}
