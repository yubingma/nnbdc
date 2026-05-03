package beidanci.api.model;

public class SimilarWordDto implements Dto {

    private String wordId;
    private String similarWordId;
    private String similarWordSpell;
    private int distance;
    private java.util.Date createTime;
    private java.util.Date updateTime;


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

    public java.util.Date getCreateTime() {
        return createTime;
    }

    public void setCreateTime(java.util.Date createTime) {
        this.createTime = createTime;
    }

    public java.util.Date getUpdateTime() {
        return updateTime;
    }

    public void setUpdateTime(java.util.Date updateTime) {
        this.updateTime = updateTime;
    }

}
