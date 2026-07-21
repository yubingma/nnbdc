package beidanci.service.bo;

import java.math.BigDecimal;
import java.util.Calendar;
import java.util.Date;
import java.util.UUID;

import javax.servlet.http.HttpServletRequest;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.Result;
import beidanci.api.model.OrderStatus;
import beidanci.api.model.PayPreOrderVo;
import beidanci.api.model.PaymentChannel;
import beidanci.service.dao.PayOrderDao;
import beidanci.service.pay.PayNotifyResult;
import beidanci.service.pay.PayStrategy;
import beidanci.service.pay.PayStrategyFactory;
import beidanci.service.po.PayOrder;
import beidanci.service.po.User;

@Service
public class PayOrderBo extends BaseBo<PayOrder> {

    private static final Logger logger = LoggerFactory.getLogger(PayOrderBo.class);

    @Autowired
    private PayStrategyFactory payStrategyFactory;

    @Autowired
    private UserBo userBo;

    @Autowired
    public PayOrderBo(PayOrderDao payOrderDao) {
        setDao(payOrderDao);
    }

    /**
     * 创建预支付订单
     */
    @Transactional
    public Result<PayPreOrderVo> createPreOrder(String userId, String productId, BigDecimal amount, PaymentChannel channel) {
        User user = userBo.findById(userId);
        if (user == null) {
            return new Result<>(false, "用户不存在", null);
        }

        PayOrder order = new PayOrder();
        order.setId("ORD_" + UUID.randomUUID().toString().replace("-", ""));
        order.setUserId(userId);
        order.setProductId(productId);
        order.setAmount(amount);
        order.setChannel(channel);
        order.setStatus(OrderStatus.PENDING);
        order.setCreateTime(new Date());
        order.setUpdateTime(new Date());

        createEntity(order);

        PayStrategy strategy = payStrategyFactory.getStrategy(channel);
        PayPreOrderVo preOrderVo = strategy.createPreOrder(user, order);

        return new Result<>(true, "预下单成功", preOrderVo);
    }

    /**
     * 处理第三方支付回调 notification (防重复、幂等开通会员)
     */
    @Transactional
    public Result<String> handlePayNotify(PaymentChannel channel, HttpServletRequest request) {
        PayStrategy strategy = payStrategyFactory.getStrategy(channel);
        PayNotifyResult notifyResult = strategy.handleNotify(request);

        if (notifyResult == null || notifyResult.getOrderId() == null) {
            return new Result<>(false, "回调解析失败", null);
        }

        PayOrder order = findById(notifyResult.getOrderId());
        if (order == null) {
            logger.error("支付回调找不到订单: orderId={}", notifyResult.getOrderId());
            return new Result<>(false, "订单不存在", null);
        }

        // 幂等防刷检查
        if (order.getStatus() == OrderStatus.SUCCESS) {
            logger.info("订单已处理成功，忽略重复回调: orderId={}", order.getId());
            return new Result<>(true, "SUCCESS", "SUCCESS");
        }

        order.setStatus(notifyResult.getStatus());
        order.setOuterTradeNo(notifyResult.getOuterTradeNo());
        order.setPayTime(notifyResult.getPayTime() != null ? notifyResult.getPayTime() : new Date());
        order.setUpdateTime(new Date());
        try {
            updateEntity(order);
        } catch (Exception e) {
            logger.error("更新订单状态失败", e);
        }

        // 如果支付成功，为用户发货（发放/延长会员权益）
        if (order.getStatus() == OrderStatus.SUCCESS) {
            fulfillMembership(order.getUserId(), order.getProductId(), channel.name());
        }

        return new Result<>(true, "SUCCESS", "SUCCESS");
    }

    /**
     * 自动发放/延长会员权益
     */
    private void fulfillMembership(String userId, String productId, String channelName) {
        User user = userBo.findById(userId);
        if (user == null) {
            return;
        }

        Date now = new Date();
        Date currentExpire = user.getVipExpireDate();
        Date baseDate = (currentExpire != null && currentExpire.after(now)) ? currentExpire : now;

        Calendar cal = Calendar.getInstance();
        cal.setTime(baseDate);

        if ("vip_annual".equalsIgnoreCase(productId) || "annual".equalsIgnoreCase(productId)) {
            cal.add(Calendar.YEAR, 1);
            user.setVipType("annual");
        } else {
            cal.add(Calendar.MONTH, 1);
            user.setVipType("monthly");
        }

        user.setVipExpireDate(cal.getTime());
        user.setLastPayChannel(channelName);
        user.setUpdateTime(now);

        try {
            userBo.updateEntity(user);
        } catch (Exception e) {
            logger.error("更新用户会员权益失败", e);
        }
        logger.info("用户会员权益开通成功: userId={}, vipExpireDate={}", userId, user.getVipExpireDate());
    }
}
