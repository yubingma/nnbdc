package beidanci.api.model;

import java.util.Date;

public class SimilarWordDto implements Dto {

    private String wordId;
    private String similarWordId;
    private String similarWordSpell;
    private int distance;
    private Date createTime;
    private Date updateTime;


    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    public String getSimilarWordId() {
        return similarWordId;
    }

    public void setSimilarWordId(String similarWordId) {
        this.similarWordId = similarWordId;
    }

    public int getDistance() {
        return distance;
    }

    public void setDistance(int distance) {
        this.distance = distance;
    }

    public String getSimilarWordSpell() {
        return similarWordSpell;
    }

    public void setSimilarWordSpell(String similarWordSpell) {
        this.similarWordSpell = similarWordSpell;
    }

    public Date getCreateTime() {
        return createTime == null ? new Date(0) : createTime;
    }

    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }

    public Date getUpdateTime() {
        return updateTime == null ? (createTime == null ? new Date(0) : createTime) : updateTime;
    }

    public void setUpdateTime(Date updateTime) {
        this.updateTime = updateTime;
    }

}
