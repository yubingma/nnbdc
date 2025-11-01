package beidanci.api.model;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

@ApiModel(description = "需求状态")
public enum FeatureRequestStatus {
    @ApiModelProperty("投票中")
    VOTING("投票中"),

    @ApiModelProperty("开发中")
    IN_PROGRESS("开发中"),

    @ApiModelProperty("已拒绝")
    REJECTED("已拒绝"),

    @ApiModelProperty("已完成")
    COMPLETED("已完成");

    private String description;

    FeatureRequestStatus(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}

