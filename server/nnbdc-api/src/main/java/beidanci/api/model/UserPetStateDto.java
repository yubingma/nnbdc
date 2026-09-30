package beidanci.api.model;

import java.util.Date;

/**
 * 记忆守护兽养成状态（每个用户一行）。
 */
public class UserPetStateDto {
    private String id;
    private String userId;

    /**
     * 进化阶段下标：0=泡芽 1=幼兽 2=灵兽 3=守护兽 4=记忆巨兽。
     */
    private Integer stageIndex;

    /**
     * 累计投喂次数，只增不减。
     */
    private Integer totalFeedings;

    /**
     * 进化系别：neutral=通用，其余由主背词库派生。
     */
    private String form;

    private Date createTime;
    private Date updateTime;

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public Integer getStageIndex() {
        return stageIndex == null ? 0 : stageIndex;
    }

    public void setStageIndex(Integer stageIndex) {
        this.stageIndex = stageIndex;
    }

    public Integer getTotalFeedings() {
        return totalFeedings == null ? 0 : totalFeedings;
    }

    public void setTotalFeedings(Integer totalFeedings) {
        this.totalFeedings = totalFeedings;
    }

    public String getForm() {
        return form == null ? "neutral" : form;
    }

    public void setForm(String form) {
        this.form = form;
    }

    public Date getCreateTime() {
        return createTime == null ? new Date(0) : createTime;
    }

    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }

    public Date getUpdateTime() {
        return updateTime == null ? (createTime == null ? new Date(0) : createTime) : updateTime;
    }

    public void setUpdateTime(Date updateTime) {
        this.updateTime = updateTime;
    }
}
