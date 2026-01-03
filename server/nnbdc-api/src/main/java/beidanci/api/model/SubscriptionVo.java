package beidanci.api.model;

import com.fasterxml.jackson.annotation.JsonFormat;
import java.util.Date;

/**
 * 订阅信息VO
 * 用于返回验证成功后的订阅详情
 */
public class SubscriptionVo extends Vo {
    
    /**
     * iOS是否为会员
     */
    private Boolean isPremiumIos;
    
    /**
     * iOS订阅到期时间
     */
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss.SSSXXX", timezone = "GMT+8")
    private Date subscriptionExpireDateIos;
    
    /**
     * iOS订阅类型：monthly/annual
     */
    private String subscriptionTypeIos;
    
    /**
     * iOS订阅状态：active/expired/cancelled
     */
    private String subscriptionStatusIos;
    
    /**
     * 产品ID
     */
    private String productId;

    public SubscriptionVo() {
    }

    public SubscriptionVo(Boolean isPremiumIos, Date subscriptionExpireDateIos, 
                         String subscriptionTypeIos, String subscriptionStatusIos, String productId) {
        this.isPremiumIos = isPremiumIos;
        this.subscriptionExpireDateIos = subscriptionExpireDateIos;
        this.subscriptionTypeIos = subscriptionTypeIos;
        this.subscriptionStatusIos = subscriptionStatusIos;
        this.productId = productId;
    }

    public Boolean getIsPremiumIos() {
        return isPremiumIos;
    }

    public void setIsPremiumIos(Boolean isPremiumIos) {
        this.isPremiumIos = isPremiumIos;
    }

    public Date getSubscriptionExpireDateIos() {
        return subscriptionExpireDateIos;
    }

    public void setSubscriptionExpireDateIos(Date subscriptionExpireDateIos) {
        this.subscriptionExpireDateIos = subscriptionExpireDateIos;
    }

    public String getSubscriptionTypeIos() {
        return subscriptionTypeIos;
    }

    public void setSubscriptionTypeIos(String subscriptionTypeIos) {
        this.subscriptionTypeIos = subscriptionTypeIos;
    }

    public String getSubscriptionStatusIos() {
        return subscriptionStatusIos;
    }

    public void setSubscriptionStatusIos(String subscriptionStatusIos) {
        this.subscriptionStatusIos = subscriptionStatusIos;
    }

    public String getProductId() {
        return productId;
    }

    public void setProductId(String productId) {
        this.productId = productId;
    }
}
