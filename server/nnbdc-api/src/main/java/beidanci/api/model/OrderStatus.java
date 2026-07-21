package beidanci.api.model;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

@ApiModel(description = "订单状态")
public enum OrderStatus {
    @ApiModelProperty("待支付")
    PENDING("待支付"),

    @ApiModelProperty("支付成功")
    SUCCESS("支付成功"),

    @ApiModelProperty("支付失败")
    FAILED("支付失败"),

    @ApiModelProperty("已退款")
    REFUNDED("已退款");

    private String description;

    private OrderStatus(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
