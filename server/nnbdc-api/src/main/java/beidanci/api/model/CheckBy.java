package beidanci.api.model;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

@ApiModel(description = "通过什么方式检查用户")
public enum CheckBy {
    @ApiModelProperty("通过电子邮件检查用户")
    Email("电子邮件"),

    @ApiModelProperty("通过用户名检查用户")
    UserName("用户名"),

    @ApiModelProperty("通过手机号检查用户")
    Phone("手机号");

    private String description;

    private CheckBy(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
