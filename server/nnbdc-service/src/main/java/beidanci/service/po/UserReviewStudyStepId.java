package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Embeddable;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;

import beidanci.api.model.StudyStep;

@Embeddable
public class UserReviewStudyStepId implements java.io.Serializable {

    private static final long serialVersionUID = 1L;

    @Column(name = "user_id", nullable = false)
    private String userId;

    @Column(name = "group_name", nullable = false, length = 20)
    private String group;

    @Column(name = "study_step", nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private StudyStep studyStep;

    public UserReviewStudyStepId() {
    }

    public UserReviewStudyStepId(String userId, String group, StudyStep studyStep) {
        this.userId = userId;
        this.group = group;
        this.studyStep = studyStep;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getGroup() {
        return group;
    }

    public void setGroup(String group) {
        this.group = group;
    }

    public StudyStep getStudyStep() {
        return studyStep;
    }

    public void setStudyStep(StudyStep studyStep) {
        this.studyStep = studyStep;
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (other == null || !(other instanceof UserReviewStudyStepId)) {
            return false;
        }
        UserReviewStudyStepId castOther = (UserReviewStudyStepId) other;
        return group.equals(castOther.group) && studyStep.equals(castOther.studyStep)
                && userId.equals(castOther.userId);
    }

    @Override
    public int hashCode() {
        int result = 17;
        result = 37 * result + userId.hashCode();
        result = 37 * result + group.hashCode();
        result = 37 * result + studyStep.hashCode();
        return result;
    }
}
