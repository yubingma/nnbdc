package beidanci.api.model;

public class UserStudyStepVo extends Vo {
    // no Java serialization

    private StudyStep studyStep;

    private UserVo user;

    /**
     * 本学习步骤在所有步骤中的顺序号，从0开始
     */
    private Integer seq;

    private StudyStepState state;

    public UserStudyStepVo() {
    }

    public UserStudyStepVo(StudyStep studyStep, Integer seq, StudyStepState state) {
        this.studyStep = studyStep;
        this.seq = seq;
        this.state = state;
    }

    public StudyStep getStudyStep() {
        return studyStep;
    }

    public void setStudyStep(StudyStep studyStep) {
        this.studyStep = studyStep;
    }

    public UserVo getUser() {
        return user;
    }

    public void setUser(UserVo user) {
        this.user = user;
    }

    public Integer getSeq() {
        return seq;
    }

    public void setSeq(Integer seq) {
        this.seq = seq;
    }

    public StudyStepState getState() {
        return state;
    }

    public void setState(StudyStepState state) {
        this.state = state;
    }
}
