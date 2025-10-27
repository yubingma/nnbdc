package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.Id;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

import beidanci.api.model.StudyStep;
import beidanci.api.model.StudyStepState;

@Entity
@Table(name = "user_study_step")
public class UserStudyStep extends Po {

    @Id
    private UserStudyStepId id;

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false, updatable = false, insertable = false)
    private User user;


    @Column(name = "studyStep", nullable = false, updatable = false, insertable = false)
    @Enumerated(EnumType.STRING)
    private StudyStep studyStep;

    /**
     * 本学习步骤在所有步骤中的顺序号，从0开始
     */
    @Column(name = "seq", nullable = false)
    private Integer seq;

    @Column(name = "state", length = 20, nullable = false)
    @Enumerated(EnumType.STRING)
    private StudyStepState state;


    /**
     * default constructor
     */
    public UserStudyStep() {
    }

    public UserStudyStep(UserStudyStepId id) {
        this.id = id;
    }


    public UserStudyStepId getId() {
        return id;
    }

    public void setId(UserStudyStepId id) {
        this.id = id;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Integer getSeq() {
        return seq;
    }

    public void setSeq(Integer index) {
        this.seq = index;
    }

    public StudyStepState getState() {
        return state;
    }

    public void setState(StudyStepState state) {
        this.state = state;
    }

    public StudyStep getStudyStep() {
        return studyStep;
    }

    public void setStudyStep(StudyStep studyStep) {
        this.studyStep = studyStep;
    }
}
