package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Table;

import beidanci.api.model.LearningDictDto;
import beidanci.service.bo.DictBo;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.WordBo;

@Entity
@Table(name = "learning_dict")
public class LearningDict extends Po {


    @Id
    private LearningDictId id;

    @Column(name = "dict_id")
    private Dict dict;

    @Column(name = "user_id")
    private User user;

    @Column(name = "is_privileged", nullable = false)
    private Boolean isPrivileged;

    /**
     * 如果某单词已经掌握，是否还是要从词书取出该单词进行学习?
     */
    @Column(name = "fetch_mastered", nullable = false)
    private Boolean fetchMastered;

    @Column(name = "sort_alg", length = 50, nullable = true)
    private String sortAlg;

    // Constructors

    /**
     * default constructor
     */
    public LearningDict() {
    }

    /**
     * minimal constructor
     */
    public LearningDict(LearningDictId id, Dict dict, User user, boolean isPrivileged, boolean fetchMastered) {
        this.id = id;
        this.dict = dict;
        this.user = user;
        this.isPrivileged = isPrivileged;
        this.fetchMastered = fetchMastered;
    }

    public Boolean getFetchMastered() {
        return fetchMastered;
    }

    public void setFetchMastered(Boolean fetchMastered) {
        this.fetchMastered = fetchMastered;
    }

    public String getSortAlg() {
        return sortAlg;
    }

    public void setSortAlg(String sortAlg) {
        this.sortAlg = sortAlg;
    }


    public LearningDictId getId() {
        return this.id;
    }

    public void setId(LearningDictId id) {
        this.id = id;
    }

    public Dict getDict() {
        return this.dict;
    }

    public void setDict(Dict dict) {
        this.dict = dict;
    }

    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Boolean getIsPrivileged() {
        return isPrivileged;
    }

    public void setIsPrivileged(Boolean isPrivileged) {
        this.isPrivileged = isPrivileged;
    }

    public static LearningDict fromDto(LearningDictDto dto, WordBo wordBo, DictBo dictBo, UserBo userBo) {
        LearningDict learningDict = new LearningDict();
        learningDict.setId(new LearningDictId(dto.getUserId(), dto.getDictId()));
        learningDict.setIsPrivileged(dto.getIsPrivileged());
        learningDict.setFetchMastered(dto.getFetchMastered());
        learningDict.setSortAlg(dto.getSortAlg());
        if (dto.getCreateTime() != null) {
            learningDict.setCreateTime(dto.getCreateTime());
        }
        if (dto.getUpdateTime() != null) {
            learningDict.setUpdateTime(dto.getUpdateTime());
        }
        if (dto.getDictId() != null) {
            learningDict.setDict(dictBo.findById(dto.getDictId()));
        }
        if (dto.getUserId() != null) {
            learningDict.setUser(userBo.findById(dto.getUserId()));
        }

        return learningDict;
    }
}
