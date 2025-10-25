package beidanci.api.model;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

@ApiModel(description = "客户端类型")
public enum ClientType {
    @ApiModelProperty("浏览器客户端")
    Browser("浏览器"),

    @ApiModelProperty("安卓客户端")
    Android("安卓"),

    @ApiModelProperty("iOS客户端")
    IOS("IOS"),

    @ApiModelProperty("macOS客户端")
    MacOS("macOS"),

    @ApiModelProperty("Linux客户端")
    Linux("Linux"),

    @ApiModelProperty("JMeter客户端")
    JMeter("JMeter");

    private String description;

    private ClientType(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
