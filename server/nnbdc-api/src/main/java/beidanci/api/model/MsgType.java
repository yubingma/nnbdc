package beidanci.api.model;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

@ApiModel(description = "消息类型")
public enum MsgType {
    @ApiModelProperty("建议")
    Advice("建议"),

    @ApiModelProperty("建议回复")
    AdviceReply("建议回复"),

    @ApiModelProperty("普通消息")
    NormalMsg("普通消息");

    private String description;

    private MsgType(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
