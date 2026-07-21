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
public class AlipayPayStrategy implements PayStrategy {

    private static final Logger logger = LoggerFactory.getLogger(AlipayPayStrategy.class);

    @Override
    public PaymentChannel getChannel() {
        return PaymentChannel.ALIPAY;
    }

    @Override
    public PayPreOrderVo createPreOrder(User user, PayOrder order) {
        logger.info("创建支付宝预支付订单: orderId={}, amount={}", order.getId(), order.getAmount());
        
        String orderInfo = "app_id=alipay_dummy&method=alipay.trade.app.pay&biz_content=...";
        Map<String, String> params = new HashMap<>();
        params.put("orderInfo", orderInfo);

        return new PayPreOrderVo(order.getId(), getChannel(), orderInfo, params);
    }

    @Override
    public PayNotifyResult handleNotify(HttpServletRequest request) {
        logger.info("收到支付宝异步回调通知");
        String orderId = request.getParameter("out_trade_no");
        String tradeNo = request.getParameter("trade_no");
        
        return new PayNotifyResult(
            orderId,
            tradeNo,
            OrderStatus.SUCCESS,
            new BigDecimal("0.00"),
            new Date(),
            "alipay_raw_notify"
        );
    }

    @Override
    public boolean queryOrderStatus(PayOrder order) {
        logger.info("查单支付宝订单状态: orderId={}", order.getId());
        return order.getStatus() == OrderStatus.SUCCESS;
    }
}
