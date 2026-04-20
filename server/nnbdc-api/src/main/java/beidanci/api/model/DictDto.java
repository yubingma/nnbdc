package beidanci.api.model;

import java.util.Date;

public class DictDto implements Dto, Ownerable {
    private String id;
    private String name;
    private String ownerId;
    /**
     * 对于用户自定义的单词书，该标志指明该单词书是否已经共享给其他用户
     */
    private Boolean isShared;
    /**
     * 该单词书是否已经准备就绪（只有准备就绪的单词书才能供用户使用，并且一旦就绪后就不能再编辑）
     */
    private Boolean isReady;
    private Boolean visible;
    /**
     * 该单词书的单词数量
     */
    private Integer wordCount;
    private Integer popularityLimit;
    private Boolean editable;
    private Boolean deletable;
    private Date createTime;
    private Date updateTime;
    private String domain;
    private String baseDictId;
    private String sortAlg;
    private String description;

    public DictDto() {
    }

    public DictDto(String id, String name, String ownerId, Boolean isShared, Boolean isReady, Boolean visible,
            Integer wordCount, Integer popularityLimit, Boolean editable, Boolean deletable, Date createTime, Date updateTime) {
        this.id = id;
        this.name = name;
        this.ownerId = ownerId;
        this.isShared = isShared;
        this.isReady = isReady;
        this.visible = visible;
        this.wordCount = wordCount;
        this.popularityLimit = popularityLimit;
        this.editable = editable;
        this.deletable = deletable;
        this.createTime = createTime;
        this.updateTime = updateTime;
    }

    public DictDto(String id, String name, String ownerId, Boolean isShared, Boolean isReady, Boolean visible,
            Integer wordCount, Integer popularityLimit, Boolean editable, Boolean deletable, Date createTime, Date updateTime, String domain) {
        this(id, name, ownerId, isShared, isReady, visible, wordCount, popularityLimit, editable, deletable, createTime, updateTime);
        this.domain = domain;
    }

    public DictDto(String id, String name, String ownerId, Boolean isShared, Boolean isReady, Boolean visible,
            Integer wordCount, Integer popularityLimit, Boolean editable, Boolean deletable, Date createTime, Date updateTime, String domain, String baseDictId, String sortAlg, String description) {
        this(id, name, ownerId, isShared, isReady, visible, wordCount, popularityLimit, editable, deletable, createTime, updateTime, domain, baseDictId, sortAlg);
        this.description = description;
    }

    public Boolean getDeletable() {
        return deletable;
    }

    public void setDeletable(Boolean deletable) {
        this.deletable = deletable;
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

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public Boolean getIsShared() {
        return isShared;
    }

    public void setIsShared(Boolean isShared) {
        this.isShared = isShared;
    }

    public Boolean getIsReady() {
        return isReady;
    }

    public void setIsReady(Boolean isReady) {
        this.isReady = isReady;
    }

    public Boolean getVisible() {
        return visible;
    }

    public void setVisible(Boolean visible) {
        this.visible = visible;
    }

    public Integer getWordCount() {
        return wordCount;
    }

    public void setWordCount(Integer wordCount) {
        this.wordCount = wordCount;
    }

    public String getOwnerId() {
        return ownerId;
    }

    public void setOwnerId(String ownerId) {
        this.ownerId = ownerId;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public Integer getPopularityLimit() {
        return popularityLimit;
    }

    public void setPopularityLimit(Integer popularityLimit) {
        this.popularityLimit = popularityLimit;
    }

    public Boolean getEditable() {
        return editable;
    }

    public void setEditable(Boolean editable) {
        this.editable = editable;
    }

    public String getDomain() {
        return domain;
    }

    public void setDomain(String domain) {
        this.domain = domain;
    }

    public String getBaseDictId() {
        return baseDictId;
    }

    public void setBaseDictId(String baseDictId) {
        this.baseDictId = baseDictId;
    }

    public String getSortAlg() {
        return sortAlg;
    }

    public void setSortAlg(String sortAlg) {
        this.sortAlg = sortAlg;
    }
    
    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

}
