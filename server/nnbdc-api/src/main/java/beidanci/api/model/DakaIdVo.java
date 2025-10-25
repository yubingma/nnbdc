package beidanci.api.model;

import java.util.Date;

public class DakaIdVo extends Vo {

    // no Java serialization
    private String userId;

    private Date forLearningDate;

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public Date getForLearningDate() {
        return forLearningDate;
    }

    public void setForLearningDate(Date forLearningDate) {
        this.forLearningDate = forLearningDate;
    }
}
