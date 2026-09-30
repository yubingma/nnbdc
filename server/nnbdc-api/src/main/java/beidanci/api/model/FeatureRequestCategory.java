package beidanci.api.model;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

@ApiModel(description = "需求分类")
public enum FeatureRequestCategory {
    @ApiModelProperty("背词复习")
    VOCABULARY("背词复习"),

    @ApiModelProperty("词典查词")
    DICTIONARY("词典查词"),

    @ApiModelProperty("游戏与互动")
    INTERACTION("游戏与互动"),

    @ApiModelProperty("界面与体验")
    EXPERIENCE("界面与体验"),

    @ApiModelProperty("其他建议")
    OTHER("其他建议");

    private String description;

    FeatureRequestCategory(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
