package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

import beidanci.api.model.UserPetStateDto;
import beidanci.service.util.Util;

/**
 * 记忆守护兽养成状态（每个用户一行）。
 */
@Entity
@Table(name = "user_pet_state")
public class UserPetState extends UuidPo {

    @Column(name = "user_id")
    private User user;

    /**
     * 进化阶段下标：0=泡芽 1=幼兽 2=灵兽 3=守护兽 4=记忆巨兽。
     */
    @Column(name = "stage_index", nullable = false)
    private Integer stageIndex;

    /**
     * 累计投喂次数，只增不减。
     */
    @Column(name = "total_feedings", nullable = false)
    private Integer totalFeedings;

    /**
     * 进化系别：neutral=通用，其余由主背词库派生。
     */
    @Column(name = "form", nullable = false, length = 20)
    private String form;

    public UserPetState() {
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Integer getStageIndex() {
        return stageIndex;
    }

    public void setStageIndex(Integer stageIndex) {
        this.stageIndex = stageIndex;
    }

    public Integer getTotalFeedings() {
        return totalFeedings;
    }

    public void setTotalFeedings(Integer totalFeedings) {
        this.totalFeedings = totalFeedings;
    }

    public String getForm() {
        return form;
    }

    public void setForm(String form) {
        this.form = form;
    }

    public static UserPetState fromDto(UserPetStateDto dto) {
        UserPetState state = new UserPetState();

        String id = dto.getId();
        if (id == null || id.length() > 32) {
            id = Util.uuid();
        }
        state.setId(id);
        state.setStageIndex(dto.getStageIndex());
        state.setTotalFeedings(dto.getTotalFeedings());
        state.setForm(dto.getForm());
        state.setCreateTime(dto.getCreateTime());
        state.setUpdateTime(dto.getUpdateTime());
        return state;
    }
}
