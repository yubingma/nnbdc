package beidanci.service.pay;

import java.math.BigDecimal;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

import javax.servlet.http.HttpServletRequest;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import beidanci.api.model.OrderStatus;
import beidanci.api.model.PayPreOrderVo;
import beidanci.api.model.PaymentChannel;
import beidanci.service.po.PayOrder;
import beidanci.service.po.User;

@Service
public class WeChatPayStrategy implements PayStrategy {

    private static final Logger logger = LoggerFactory.getLogger(WeChatPayStrategy.class);

    @Override
    public PaymentChannel getChannel() {
        return PaymentChannel.WECHAT;
    }

    @Override
    public PayPreOrderVo createPreOrder(User user, PayOrder order) {
        logger.info("创建微信预支付订单: orderId={}, amount={}", order.getId(), order.getAmount());
        
        Map<String, String> params = new HashMap<>();
        params.put("appid", "wx_dummy_appid");
        params.put("partnerid", "wx_dummy_mchid");
        params.put("prepayid", "wx_prepay_" + order.getId());
        params.put("package", "Sign=WXPay");
        params.put("noncestr", String.valueOf(System.currentTimeMillis()));
        params.put("timestamp", String.valueOf(System.currentTimeMillis() / 1000));
        params.put("sign", "dummy_sign");

        return new PayPreOrderVo(order.getId(), getChannel(), "wx_prepay_" + order.getId(), params);
    }

    @Override
    public PayNotifyResult handleNotify(HttpServletRequest request) {
        logger.info("收到微信支付异步回调通知");
        String orderId = request.getParameter("out_trade_no");
        String transactionId = request.getParameter("transaction_id");
        
        return new PayNotifyResult(
            orderId,
            transactionId,
            OrderStatus.SUCCESS,
            new BigDecimal("0.00"),
            new Date(),
            "wechat_raw_notify"
        );
    }

    @Override
    public boolean queryOrderStatus(PayOrder order) {
        logger.info("查单微信订单状态: orderId={}", order.getId());
        return order.getStatus() == OrderStatus.SUCCESS;
    }
}
