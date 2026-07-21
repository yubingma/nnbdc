package beidanci.api.model;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

@ApiModel(description = "支付渠道")
public enum PaymentChannel {
    @ApiModelProperty("微信支付")
    WECHAT("微信支付"),

    @ApiModelProperty("支付宝")
    ALIPAY("支付宝"),

    @ApiModelProperty("华为支付")
    HUAWEI_IAP("华为支付"),

    @ApiModelProperty("小米支付")
    XIAOMI_IAP("小米支付"),

    @ApiModelProperty("OPPO支付")
    OPPO_IAP("OPPO支付"),

    @ApiModelProperty("VIVO支付")
    VIVO_IAP("VIVO支付"),

    @ApiModelProperty("苹果内购")
    APPLE_IAP("苹果内购");

    private String description;

    private PaymentChannel(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
