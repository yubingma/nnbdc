package beidanci.api.model;

import java.util.Date;

/**
 * 打卡记录DTO
 */
public class DakaDto extends Dto {

    private String userId;
    private Date forLearningDate;
    private String text;
    // 客户端 Dakas 表字段名是 textContent，与服务端 text 等价。保留别名以兼容客户端同步往返。
    private String textContent;

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

    public String getTextContent() {
        return textContent;
    }

    public void setTextContent(String textContent) {
        this.textContent = textContent;
    }

    /**
     * 客户端可能传 text 或 textContent（Dakas 表字段名），取非空的那个作为打卡正文。
     */
    public String effectiveText() {
        return text != null ? text : textContent;
    }

}
