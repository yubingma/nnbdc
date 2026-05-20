package beidanci.api.model;

import java.util.Date;

/**
 * 错词DTO
 */
public class WrongWordDto extends Dto {

    private String userId;
    private String wordId;

    public WrongWordDto() {
    }

    public WrongWordDto(String userId, String wordId, Date createTime, Date updateTime) {
        this.userId = userId;
        this.wordId = wordId;
        this.createTime = createTime;
        this.updateTime = updateTime;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

}
