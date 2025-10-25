package beidanci.api.model;

import java.util.Date;

/**
 * 单词短描述中文翻译DTO
 */
public class WordShortDescChineseDto implements Dto {
    private String id;
    private String wordId;
    private String content;
    private Integer hand;
    private Integer foot;
    private String authorId;
    private Date createTime;
    private Date updateTime;

    public WordShortDescChineseDto() {
    }

    public WordShortDescChineseDto(String id, String wordId, String content,
                                   Integer hand, Integer foot, String authorId,
                                   Date createTime, Date updateTime) {
        this.id = id;
        this.wordId = wordId;
        this.content = content;
        this.hand = hand;
        this.foot = foot;
        this.authorId = authorId;
        this.createTime = createTime;
        this.updateTime = updateTime;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public Integer getHand() {
        return hand;
    }

    public void setHand(Integer hand) {
        this.hand = hand;
    }

    public Integer getFoot() {
        return foot;
    }

    public void setFoot(Integer foot) {
        this.foot = foot;
    }

    public String getAuthorId() {
        return authorId;
    }

    public void setAuthorId(String authorId) {
        this.authorId = authorId;
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

