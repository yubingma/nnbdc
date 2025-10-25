package beidanci.api.model;

public class WordAdditionalInfoVo extends UuidVo {
    private String word;
    private String content;
    private int handCount;
    private int footCount;
    private String createdBy;
    private String createdByNickName;
    private boolean votedByMe; // 我是否已经为该内容投过票了

    @Override
    public String getId() {
        return id;
    }

    @Override
    public void setId(String id) {
        this.id = id;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public int getHandCount() {
        return handCount;
    }

    public void setHandCount(int handCount) {
        this.handCount = handCount;
    }

    public int getFootCount() {
        return footCount;
    }

    public void setFootCount(int footCount) {
        this.footCount = footCount;
    }

    public String getWord() {
        return word;
    }

    public void setWord(String word) {
        this.word = word;
    }

    public boolean isVotedByMe() {
        return votedByMe;
    }

    public void setVotedByMe(boolean votedByMe) {
        this.votedByMe = votedByMe;
    }

    public String getCreatedBy() {
        return createdBy;
    }

    public void setCreatedBy(String createdBy) {
        this.createdBy = createdBy;
    }

    public String getCreatedByNickName() {
        return createdByNickName;
    }

    public void setCreatedByNickName(String createdByNickName) {
        this.createdByNickName = createdByNickName;
    }

}
