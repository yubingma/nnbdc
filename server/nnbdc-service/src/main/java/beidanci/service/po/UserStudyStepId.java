package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Embeddable;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;

import beidanci.api.model.StudyStep;

@Embeddable
public class UserStudyStepId implements java.io.Serializable {

    private static final long serialVersionUID = 1L;

    // Fields


    @Column(name = "userId", nullable = false)
    private String userId;

    @Column(name = "studyStep", nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private StudyStep studyStep;

    public UserStudyStepId() {
    }

    public UserStudyStepId(String userId, StudyStep studyStep) {
        this.userId = userId;
        this.studyStep = studyStep;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public StudyStep getStudyStep() {
        return studyStep;
    }

    public void setStudyStep(StudyStep studyStep) {
        this.studyStep = studyStep;
    }

    @Override
    public boolean equals(Object other) {
        if ((this == other))
            return true;
        if ((other == null))
            return false;
        if (!(other instanceof UserStudyStepId))
            return false;
        UserStudyStepId castOther = (UserStudyStepId) other;

        return studyStep.equals(castOther.studyStep) && userId.equals(castOther.userId);
    }

    @Override
    public int hashCode() {
        int result = 17;

        result = 37 * result + userId.hashCode();
        result = 37 * result + studyStep.hashCode();
        return result;
    }

}
