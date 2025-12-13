package beidanci.service.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.service.bo.SubscriptionBo;

/**
 * 订阅相关接口
 */
@RestController
public class SubscriptionController {

    @Autowired
    private SubscriptionBo subscriptionBo;

    /**
     * 验证订阅收据
     * 
     * @param userId 用户ID
     * @param receiptData Base64编码的收据数据
     * @param productId 产品ID
     * @param transactionId 交易ID
     * @param platform 平台类型：ios/android
     * @return 验证结果
     */
    @PostMapping("/verifySubscription.do")
    public Result<Void> verifySubscription(
            @RequestParam String userId,
            @RequestParam String receiptData,
            @RequestParam String productId,
            @RequestParam(required = false) String transactionId,
            @RequestParam String platform) {
        return subscriptionBo.verifySubscription(userId, receiptData, productId, transactionId, platform);
    }

    /**
     * 恢复购买
     * 
     * @param userId 用户ID
     * @return 恢复结果
     */
    @PostMapping("/restoreSubscription.do")
    public Result<Void> restoreSubscription(@RequestParam String userId) {
        return subscriptionBo.restoreSubscription(userId);
    }
}

