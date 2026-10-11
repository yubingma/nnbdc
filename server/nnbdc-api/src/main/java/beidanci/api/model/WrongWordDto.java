package beidanci.api.model;

import java.util.Date;

/**
 * 错词DTO
 */
public class WrongWordDto extends Dto {

    private String userId;
    private String wordId;
    private Integer wrongCount;
    private Boolean inWrongBook;

    public WrongWordDto() {
    }

    public WrongWordDto(String userId, String wordId, Date createTime, Date updateTime) {
        this(userId, wordId, 1, true, createTime, updateTime);
    }

    public WrongWordDto(String userId, String wordId, Integer wrongCount, Boolean inWrongBook, Date createTime, Date updateTime) {
        this.userId = userId;
        this.wordId = wordId;
        this.wrongCount = wrongCount;
        this.inWrongBook = inWrongBook;
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

    public Integer getWrongCount() {
        return wrongCount;
    }

    public void setWrongCount(Integer wrongCount) {
        this.wrongCount = wrongCount;
    }

    public Boolean getInWrongBook() {
        return inWrongBook;
    }

    public void setInWrongBook(Boolean inWrongBook) {
        this.inWrongBook = inWrongBook;
    }

}
