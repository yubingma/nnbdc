package beidanci.api.model;

import java.util.Date;

/**
 * 书签数据传输对象
 */
public class BookMarkDto {
    // 用户ID
    private String userId;

    // 书签名称
    private String bookMarkName;

    // 书签记录的单词位置（从0开始），并且这个位置是对所有单词而言（包括服务端的）
    private int position;

    // 书签记录的单词拼写
    private String spell;

    // 创建时间
    private Date createTime;

    // 更新时间
    private Date updateTime;

    public BookMarkDto() {
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getBookMarkName() {
        return bookMarkName;
    }

    public void setBookMarkName(String bookMarkName) {
        this.bookMarkName = bookMarkName;
    }

    public int getPosition() {
        return position;
    }

    public void setPosition(int position) {
        this.position = position;
    }

    public String getSpell() {
        return spell;
    }

    public void setSpell(String spell) {
        this.spell = spell;
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
