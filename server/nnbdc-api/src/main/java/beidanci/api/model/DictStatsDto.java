package beidanci.api.model;

import java.util.Date;

/**
 * 词典统计信息DTO
 */
public class DictStatsDto {
    private String id;
    private String name;
    private String ownerId;
    private Boolean isShared;
    private Boolean isReady;
    private Boolean visible;
    private Integer wordCount;
    private Integer popularityLimit;
    private Date createTime;
    private Date updateTime;
    
    // 统计信息
    private Long userSelectionCount; // 被用户选择的数量
    private Long totalUsers; // 总用户数
    private Double selectionRate; // 选择率
    
    public DictStatsDto() {
    }
    
    public DictStatsDto(String id, String name, String ownerId, Boolean isShared, 
                       Boolean isReady, Boolean visible, Integer wordCount, 
                       Date createTime, Date updateTime) {
        this.id = id;
        this.name = name;
        this.ownerId = ownerId;
        this.isShared = isShared;
        this.isReady = isReady;
        this.visible = visible;
        this.wordCount = wordCount;
        this.createTime = createTime;
        this.updateTime = updateTime;
    }
    
    // Getters and Setters
    public String getId() {
        return id;
    }
    
    public void setId(String id) {
        this.id = id;
    }
    
    public String getName() {
        return name;
    }
    
    public void setName(String name) {
        this.name = name;
    }
    
    public String getOwnerId() {
        return ownerId;
    }
    
    public void setOwnerId(String ownerId) {
        this.ownerId = ownerId;
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
    
    public Integer getPopularityLimit() {
        return popularityLimit;
    }
    
    public void setPopularityLimit(Integer popularityLimit) {
        this.popularityLimit = popularityLimit;
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
    
    public Long getUserSelectionCount() {
        return userSelectionCount;
    }
    
    public void setUserSelectionCount(Long userSelectionCount) {
        this.userSelectionCount = userSelectionCount;
    }
    
    public Long getTotalUsers() {
        return totalUsers;
    }
    
    public void setTotalUsers(Long totalUsers) {
        this.totalUsers = totalUsers;
    }
    
    public Double getSelectionRate() {
        return selectionRate;
    }
    
    public void setSelectionRate(Double selectionRate) {
        this.selectionRate = selectionRate;
    }
}
