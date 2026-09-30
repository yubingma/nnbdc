package beidanci.api.model;

public class FeatureRequestVo extends UuidVo {
    private String title;
    private String content;
    private FeatureRequestStatus status;
    private FeatureRequestCategory category;
    private Integer voteCount;
    private UserVo creator;

    public FeatureRequestCategory getCategory() {
        return category;
    }

    public void setCategory(FeatureRequestCategory category) {
        this.category = category;
    }

    public String getTitle() {
        return title;
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public FeatureRequestStatus getStatus() {
        return status;
    }

    public void setStatus(FeatureRequestStatus status) {
        this.status = status;
    }

    public Integer getVoteCount() {
        return voteCount;
    }

    public void setVoteCount(Integer voteCount) {
        this.voteCount = voteCount;
    }

    public UserVo getCreator() {
        return creator;
    }

    public void setCreator(UserVo creator) {
        this.creator = creator;
    }
}

