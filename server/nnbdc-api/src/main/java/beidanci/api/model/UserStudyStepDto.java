package beidanci.api.model;

import java.util.Date;

/**
 * 用户学习步骤DTO（单表三组结构：scope 区分新词/旧词，group 区分测评/答对后/答错后）
 */
public class UserStudyStepDto extends Dto {

    private String userId;
    /** 'new' 新词 / 'review' 旧词 */
    private String scope;
    /** 'check' 测评 / 'correct' 答对后 / 'wrong' 答错后（JSON 字段名 group） */
    private String group;
    private StudyStep studyStep;
    private Integer seq;
    private StudyStepState state;

    public UserStudyStepDto() {
    }

    public UserStudyStepDto(String userId, String scope, String group, StudyStep studyStep, Integer seq,
            StudyStepState state, Date createTime, Date updateTime) {
        this.userId = userId;
        this.scope = scope;
        this.group = group;
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

    public String getScope() {
        return scope;
    }

    public void setScope(String scope) {
        this.scope = scope;
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
