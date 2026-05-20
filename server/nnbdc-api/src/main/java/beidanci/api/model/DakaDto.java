package beidanci.api.model;

import java.util.Date;

/**
 * 打卡记录DTO
 */
public class DakaDto extends Dto {

    private String userId;
    private Date forLearningDate;
    private String text;

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

}
