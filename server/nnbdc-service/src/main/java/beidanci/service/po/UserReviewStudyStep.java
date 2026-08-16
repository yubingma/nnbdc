package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.Id;
import javax.persistence.Table;

import beidanci.api.model.StudyStep;

/**
 * 旧词（复习词）三组学习规则条目（用户数据，经 db_log 同步备份）
 */
@Entity
@Table(name = "user_review_study_step")
public class UserReviewStudyStep extends Po {

    @Id
    private UserReviewStudyStepId id;

    @Column(name = "user_id")
    private User user;

    @Column(name = "study_step", nullable = false, updatable = false, insertable = false)
    @Enumerated(EnumType.STRING)
    private StudyStep studyStep;

    @Column(name = "seq", nullable = false)
    private Integer seq;

    @Column(name = "state", length = 20, nullable = false)
    private String state; // 'Active' / 'Inactive'

    public UserReviewStudyStep() {
    }

    public UserReviewStudyStep(UserReviewStudyStepId id) {
        this.id = id;
    }

    public UserReviewStudyStepId getId() {
        return id;
    }

    public void setId(UserReviewStudyStepId id) {
        this.id = id;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public StudyStep getStudyStep() {
        return studyStep;
    }

    public void setStudyStep(StudyStep studyStep) {
        this.studyStep = studyStep;
    }

    public Integer getSeq() {
        return seq;
    }

    public void setSeq(Integer seq) {
        this.seq = seq;
    }

    public String getState() {
        return state;
    }

    public void setState(String state) {
        this.state = state;
    }
}
