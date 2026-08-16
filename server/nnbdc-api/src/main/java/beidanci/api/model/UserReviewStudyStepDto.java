package beidanci.api.model;

import java.util.Date;

/**
 * 旧词（复习词）三组学习规则条目 DTO
 * group: 'check'（测评环节，单选）/ 'correct'（答对后序列）/ 'wrong'（答错后序列）
 */
public class UserReviewStudyStepDto extends Dto {

    private String userId;
    private String group;
    private StudyStep studyStep;
    private Integer seq;
    private String state; // 'Active' / 'Inactive'

    public UserReviewStudyStepDto() {
    }

    public UserReviewStudyStepDto(String userId, String group, StudyStep studyStep, Integer seq, String state,
            Date createTime, Date updateTime) {
        this.userId = userId;
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

    public String getState() {
        return state;
    }

    public void setState(String state) {
        this.state = state;
    }
}
