package beidanci.api.model;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

/**
 * 消息级需求的处理状态。
 *
 * 与需求墙的 FeatureRequestStatus 档位完全一致（投票中 / 开发中 / 已拒绝 / 已完成），
 * 管理员在两个入口看到的状态叫法一样，不用另学一套。两者是两套独立数据，枚举也各自独立。
 */
@ApiModel(description = "消息级需求处理状态")
public enum AdviceRequirementStatus {
    @ApiModelProperty("投票中")
    VOTING("投票中"),

    @ApiModelProperty("开发中")
    IN_PROGRESS("开发中"),

    @ApiModelProperty("已拒绝")
    REJECTED("已拒绝"),

    @ApiModelProperty("已完成")
    COMPLETED("已完成");

    private String description;

    AdviceRequirementStatus(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
