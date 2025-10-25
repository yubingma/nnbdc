package beidanci.api.model;

import java.util.Date;

public class SynonymDto implements Dto {
    /**
     * 本单词的一个释义项
     */
    private String meaningItemId;

    /**
     * 近义词的ID
     */
    private String wordId;

    private String spell;

    private Date createTime; // 创建时间
    private Date updateTime; // 更新时间

    public String getMeaningItemId() {
        return meaningItemId;
    }

    public void setMeaningItemId(String meaningItemId) {
        this.meaningItemId = meaningItemId;
    }

    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
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

    public String getSpell() {
        return spell;
    }

    public void setSpell(String spell) {
        this.spell = spell;
    }
}
