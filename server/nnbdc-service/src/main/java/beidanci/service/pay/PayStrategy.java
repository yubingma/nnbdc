package beidanci.service.pay;

import javax.servlet.http.HttpServletRequest;

import beidanci.api.model.PayPreOrderVo;
import beidanci.api.model.PaymentChannel;
import beidanci.service.po.PayOrder;
import beidanci.service.po.User;

public interface PayStrategy {

    /**
     * 获取支持的支付渠道
     */
    PaymentChannel getChannel();

    /**
     * 创建预支付订单 (生成给客户端唤起 SDK 的数据)
     */
    PayPreOrderVo createPreOrder(User user, PayOrder order);

    /**
     * 处理异步回调 Webhook
     */
    PayNotifyResult handleNotify(HttpServletRequest request);

    /**
     * 主动查询订单状态
     */
    boolean queryOrderStatus(PayOrder order);
}
