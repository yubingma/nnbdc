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

    @Column(name = "user_id", nullable = false)
    private String userId;

    /** 'new' 新词 / 'review' 旧词 */
    @Column(name = "scope", nullable = false, length = 10)
    private String scope;

    /** 'check' 测评 / 'correct' 答对后 / 'wrong' 答错后 */
    @Column(name = "group_name", nullable = false, length = 20)
    private String groupName;

    @Column(name = "study_step", nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private StudyStep studyStep;

    public UserStudyStepId() {
    }

    public UserStudyStepId(String userId, String scope, String groupName, StudyStep studyStep) {
        this.userId = userId;
        this.scope = scope;
        this.groupName = groupName;
        this.studyStep = studyStep;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getScope() {
        return scope;
    }

    public void setScope(String scope) {
        this.scope = scope;
    }

    public String getGroupName() {
        return groupName;
    }

    public void setGroupName(String groupName) {
        this.groupName = groupName;
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

        return studyStep.equals(castOther.studyStep) && userId.equals(castOther.userId)
                && scope.equals(castOther.scope) && groupName.equals(castOther.groupName);
    }

    @Override
    public int hashCode() {
        int result = 17;

        result = 37 * result + userId.hashCode();
        result = 37 * result + scope.hashCode();
        result = 37 * result + groupName.hashCode();
        result = 37 * result + studyStep.hashCode();
        return result;
    }

}
