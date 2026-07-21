package beidanci.api.model;

import java.util.Map;

/**
 * 预下单响应 VO (用于客户端 SDK 唤起支付)
 */
public class PayPreOrderVo {
    private String orderId;
    private PaymentChannel channel;
    private String payData;
    private Map<String, String> payParams;

    public PayPreOrderVo() {
    }

    public PayPreOrderVo(String orderId, PaymentChannel channel, String payData, Map<String, String> payParams) {
        this.orderId = orderId;
        this.channel = channel;
        this.payData = payData;
        this.payParams = payParams;
    }

    public String getOrderId() {
        return orderId;
    }

    public void setOrderId(String orderId) {
        this.orderId = orderId;
    }

    public PaymentChannel getChannel() {
        return channel;
    }

    public void setChannel(PaymentChannel channel) {
        this.channel = channel;
    }

    public String getPayData() {
        return payData;
    }

    public void setPayData(String payData) {
        this.payData = payData;
    }

    public Map<String, String> getPayParams() {
        return payParams;
    }

    public void setPayParams(Map<String, String> payParams) {
        this.payParams = payParams;
    }
}
