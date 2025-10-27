package beidanci.api.model;

import java.util.Date;

/**
 * 用户学习步骤DTO
 */
public class UserStudyStepDto implements Dto {

    private String userId;
    private StudyStep studyStep;
    private Integer seq;
    private StudyStepState state;
    private Date createTime;
    private Date updateTime;

    public UserStudyStepDto() {
    }

    public UserStudyStepDto(String userId, StudyStep studyStep, Integer seq, StudyStepState state, Date createTime, Date updateTime) {
        this.userId = userId;
        this.studyStep = studyStep;
        this.seq = seq;
        this.state = state;
        this.createTime = createTime;
        this.updateTime = updateTime;
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

    public Date getCreateTime() {
        return createTime;
    }

    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }

    public Date getUpdateTime() {
        return updateTime;
    }

    public void setUpdateTime(Date updateTime) {
        this.updateTime = updateTime;
    }
}
