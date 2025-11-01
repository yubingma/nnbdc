package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

import beidanci.api.model.FeatureRequestStatus;

@Entity
@Table(name = "feature_request")
public class FeatureRequest extends UuidPo {

    @ManyToOne
    @JoinColumn(name = "creatorId", nullable = false)
    private User creator;

    @Column(name = "title", length = 200, nullable = false)
    private String title;

    @Column(name = "content", length = 5000)
    private String content;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 20)
    private FeatureRequestStatus status;

    @Column(name = "voteCount", nullable = false)
    private Integer voteCount;

    public FeatureRequest() {
        this.voteCount = 0;
        this.status = FeatureRequestStatus.VOTING;
    }

    public User getCreator() {
        return creator;
    }

    public void setCreator(User creator) {
        this.creator = creator;
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
}

