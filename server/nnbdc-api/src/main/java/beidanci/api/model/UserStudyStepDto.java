package beidanci.api.model;

import java.util.Date;

/**
 * 用户学习步骤DTO
 */
public class UserStudyStepDto implements Dto {

    private String userId;
    private StudyStep studyStep;
    private Integer index;
    private StudyStepState state;
    private Date createTime;
    private Date updateTime;

    public UserStudyStepDto() {
    }

    public UserStudyStepDto(String userId, StudyStep studyStep, Integer index, StudyStepState state, Date createTime, Date updateTime) {
        this.userId = userId;
        this.studyStep = studyStep;
        this.index = index;
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

    public Integer getIndex() {
        return index;
    }

    public void setIndex(Integer index) {
        this.index = index;
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
