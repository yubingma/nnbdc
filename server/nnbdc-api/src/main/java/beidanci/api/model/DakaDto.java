package beidanci.api.model;

import java.util.Date;

/**
 * 打卡记录DTO
 */
public class DakaDto implements Dto {

    private String userId;
    private Date forLearningDate;
    private String text;
    private Date createTime;
    private Date updateTime;

    public DakaDto() {
    }

    public DakaDto(String userId, Date forLearningDate, String text, Date createTime, Date updateTime) {
        this.userId = userId;
        this.forLearningDate = forLearningDate;
        this.text = text;
        this.createTime = createTime;
        this.updateTime = updateTime;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public Date getForLearningDate() {
        return forLearningDate;
    }

    public void setForLearningDate(Date forLearningDate) {
        this.forLearningDate = forLearningDate;
    }

    public String getText() {
        return text;
    }

    public void setText(String text) {
        this.text = text;
    }

    public Date getCreateTime() {
        return createTime;
    }

    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }

    public Date getUpdateTime() {
        return updateTime;
    }

    public void setUpdateTime(Date updateTime) {
        this.updateTime = updateTime;
    }
}
