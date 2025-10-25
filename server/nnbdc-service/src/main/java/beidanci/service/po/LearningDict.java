package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
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

    @ManyToOne
    @JoinColumn(name = "dictId", nullable = false, updatable = false, insertable = false)
    private Dict dict;

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false, updatable = false, insertable = false)
    private User user;

    @ManyToOne
    @JoinColumn(name = "currentWordId", updatable = false, insertable = false)
    private Word currentWord;

    @Column(name = "currentWordSeq")
    private Integer currentWordSeq;

    @Column(name = "IsPrivileged", nullable = false)
    private Boolean isPrivileged;

    /**
     * 如果某单词已经掌握，是否还是要从词书取出该单词进行学习?
     */
    @Column(name = "fetchMastered", nullable = false)
    private Boolean fetchMastered;

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

    public Word getCurrentWord() {
        return this.currentWord;
    }

    public void setCurrentWord(Word currentWord) {
        this.currentWord = currentWord;
    }

    public Integer getCurrentWordSeq() {
        return this.currentWordSeq;
    }

    public void setCurrentWordSeq(Integer currentWordSeq) {
        this.currentWordSeq = currentWordSeq;
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
        learningDict.setCurrentWordSeq(dto.getCurrentWordSeq());
        if (dto.getCurrentWord() != null) {
            learningDict.setCurrentWord(wordBo.findById(dto.getCurrentWord()));
        }
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
