package beidanci.service.pay;

import java.math.BigDecimal;
import java.util.Date;

import beidanci.api.model.OrderStatus;

public class PayNotifyResult {
    private String orderId;
    private String outerTradeNo;
    private OrderStatus status;
    private BigDecimal amount;
    private Date payTime;
    private String rawData;

    public PayNotifyResult() {
    }

    public PayNotifyResult(String orderId, String outerTradeNo, OrderStatus status, BigDecimal amount, Date payTime, String rawData) {
        this.orderId = orderId;
        this.outerTradeNo = outerTradeNo;
        this.status = status;
        this.amount = amount;
        this.payTime = payTime;
        this.rawData = rawData;
    }

    public String getOrderId() {
        return orderId;
    }

    public void setOrderId(String orderId) {
        this.orderId = orderId;
    }

    public String getOuterTradeNo() {
        return outerTradeNo;
    }

    public void setOuterTradeNo(String outerTradeNo) {
        this.outerTradeNo = outerTradeNo;
    }

    public OrderStatus getStatus() {
        return status;
    }

    public void setStatus(OrderStatus status) {
        this.status = status;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }

    public Date getPayTime() {
        return payTime;
    }

    public void setPayTime(Date payTime) {
        this.payTime = payTime;
    }

    public String getRawData() {
        return rawData;
    }

    public void setRawData(String rawData) {
        this.rawData = rawData;
    }
}
