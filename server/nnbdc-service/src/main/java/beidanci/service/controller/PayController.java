package beidanci.service.controller;

import java.math.BigDecimal;

import javax.servlet.http.HttpServletRequest;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.PayPreOrderVo;
import beidanci.api.model.PaymentChannel;
import beidanci.service.bo.PayOrderBo;

/**
 * 通用支付控制器
 */
@RestController
@RequestMapping("/pay")
public class PayController {

    @Autowired
    private PayOrderBo payOrderBo;

    /**
     * 创建预支付订单
     */
    @PostMapping("/createPreOrder.do")
    public Result<PayPreOrderVo> createPreOrder(
            @RequestParam String userId,
            @RequestParam String productId,
            @RequestParam BigDecimal amount,
            @RequestParam PaymentChannel channel) {
        return payOrderBo.createPreOrder(userId, productId, amount, channel);
    }

    /**
     * 第三方支付异步回调通知 Webhook
     */
    @PostMapping("/notify/{channel}.do")
    public Result<String> handlePayNotify(@PathVariable("channel") String channelStr, HttpServletRequest request) {
        PaymentChannel channel = PaymentChannel.valueOf(channelStr.toUpperCase());
        return payOrderBo.handlePayNotify(channel, request);
    }
}
