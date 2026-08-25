package beidanci.api.model;

public class BadgeVo extends UuidVo {
    private String code;
    private String name;
    private String category;
    private String tier;
    private Boolean isStackable;
    private String conditionType;
    private Integer targetValue;
    private Integer rewardBubbles;
    private String description;
    private Integer displayOrder;

    public BadgeVo() {
    }

    public static BadgeVo fromBadge(Badge badge) {
        if (badge == null) return null;
        BadgeVo vo = new BadgeVo();
        vo.setId(badge.name());
        vo.setCode(badge.name());
        vo.setName(badge.getDisplayName());
        vo.setCategory(badge.getCategory());
        vo.setTier(badge.getTier());
        vo.setIsStackable(badge.isStackable());
        vo.setConditionType(badge.getConditionType());
        vo.setTargetValue(badge.getTargetValue());
        vo.setRewardBubbles(badge.getRewardBubbles());
        vo.setDescription(badge.getDescription());
        vo.setDisplayOrder(badge.getDisplayOrder());
        return vo;
    }

    public String getCode() {
        return code;
    }

    public void setCode(String code) {
        this.code = code;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }

    public String getTier() {
        return tier;
    }

    public void setTier(String tier) {
        this.tier = tier;
    }

    public Boolean getIsStackable() {
        return isStackable;
    }

    public void setIsStackable(Boolean isStackable) {
        this.isStackable = isStackable;
    }

    public String getConditionType() {
        return conditionType;
    }

    public void setConditionType(String conditionType) {
        this.conditionType = conditionType;
    }

    public Integer getTargetValue() {
        return targetValue;
    }

    public void setTargetValue(Integer targetValue) {
        this.targetValue = targetValue;
    }

    public Integer getRewardBubbles() {
        return rewardBubbles;
    }

    public void setRewardBubbles(Integer rewardBubbles) {
        this.rewardBubbles = rewardBubbles;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public Integer getDisplayOrder() {
        return displayOrder;
    }

    public void setDisplayOrder(Integer displayOrder) {
        this.displayOrder = displayOrder;
    }
}
