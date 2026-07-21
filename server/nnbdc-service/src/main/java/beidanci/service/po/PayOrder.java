package beidanci.service.po;

import java.math.BigDecimal;
import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.Index;
import javax.persistence.Table;

import beidanci.api.model.OrderStatus;
import beidanci.api.model.PaymentChannel;

@Entity
@Table(name = "pay_order", indexes = {
    @Index(name = "idx_payorder_userid", columnList = "user_id"),
    @Index(name = "idx_payorder_outertradeno", columnList = "outer_trade_no")
})
public class PayOrder extends UuidPo {

    @Column(name = "user_id", length = 32, nullable = false)
    private String userId;

    @Column(name = "product_id", length = 50, nullable = false)
    private String productId;

    @Column(name = "amount", precision = 10, scale = 2, nullable = false)
    private BigDecimal amount;

    @Enumerated(EnumType.STRING)
    @Column(name = "channel", length = 30, nullable = false)
    private PaymentChannel channel;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", length = 20, nullable = false)
    private OrderStatus status;

    @Column(name = "outer_trade_no", length = 128, nullable = true)
    private String outerTradeNo;

    @Column(name = "pay_time", nullable = true)
    private Date payTime;

    public PayOrder() {
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getProductId() {
        return productId;
    }

    public void setProductId(String productId) {
        this.productId = productId;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }

    public PaymentChannel getChannel() {
        return channel;
    }

    public void setChannel(PaymentChannel channel) {
        this.channel = channel;
    }

    public OrderStatus getStatus() {
        return status;
    }

    public void setStatus(OrderStatus status) {
        this.status = status;
    }

    public String getOuterTradeNo() {
        return outerTradeNo;
    }

    public void setOuterTradeNo(String outerTradeNo) {
        this.outerTradeNo = outerTradeNo;
    }

    public Date getPayTime() {
        return payTime;
    }

    public void setPayTime(Date payTime) {
        this.payTime = payTime;
    }
}
