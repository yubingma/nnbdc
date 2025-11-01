package beidanci.service.po;

import javax.persistence.Entity;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;
import javax.persistence.UniqueConstraint;

@Entity
@Table(name = "feature_request_vote", 
       uniqueConstraints = {@UniqueConstraint(columnNames = {"requestId", "userId"})})
public class FeatureRequestVote extends UuidPo {

    @ManyToOne
    @JoinColumn(name = "requestId", nullable = false)
    private FeatureRequest request;

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false)
    private User user;

    public FeatureRequestVote() {
    }

    public FeatureRequest getRequest() {
        return request;
    }

    public void setRequest(FeatureRequest request) {
        this.request = request;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }
}

