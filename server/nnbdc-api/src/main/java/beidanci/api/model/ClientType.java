package beidanci.api.model;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

@ApiModel(description = "客户端类型")
public enum ClientType {
    @ApiModelProperty("浏览器客户端")
    browser("浏览器"),

    @ApiModelProperty("安卓客户端")
    android("安卓"),

    @ApiModelProperty("iOS客户端")
    ios("iOS"),

    @ApiModelProperty("macOS客户端")
    macos("macOS"),

    @ApiModelProperty("Linux客户端")
    linux("Linux"),

    @ApiModelProperty("Windows客户端")
    windows("Windows"),

    @ApiModelProperty("JMeter客户端")
    jmeter("JMeter");

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
