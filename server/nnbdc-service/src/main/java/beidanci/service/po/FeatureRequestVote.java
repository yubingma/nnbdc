package beidanci.service.po;

import javax.persistence.Entity;
import javax.persistence.Table;
import javax.persistence.UniqueConstraint;

@Entity
@Table(name = "feature_request_vote", 
       uniqueConstraints = {@UniqueConstraint(columnNames = {"requestId", "userId"})})
public class FeatureRequestVote extends UuidPo {

    private FeatureRequest request;

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

