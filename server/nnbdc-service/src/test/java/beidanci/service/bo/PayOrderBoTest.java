package beidanci.service.bo;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.List;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

import beidanci.api.model.PayPreOrderVo;
import beidanci.api.model.PaymentChannel;
import beidanci.service.pay.AlipayPayStrategy;
import beidanci.service.pay.PayStrategy;
import beidanci.service.pay.PayStrategyFactory;
import beidanci.service.pay.WeChatPayStrategy;
import beidanci.service.po.PayOrder;
import beidanci.service.po.User;

public class PayOrderBoTest {

    @Test
    public void testPayStrategyFactoryRouting() {
        List<PayStrategy> strategies = new ArrayList<>();
        strategies.add(new WeChatPayStrategy());
        strategies.add(new AlipayPayStrategy());

        PayStrategyFactory factory = new PayStrategyFactory(strategies);

        PayStrategy wechatStrategy = factory.getStrategy(PaymentChannel.WECHAT);
        assertNotNull(wechatStrategy);
        assertEquals(PaymentChannel.WECHAT, wechatStrategy.getChannel());

        PayStrategy alipayStrategy = factory.getStrategy(PaymentChannel.ALIPAY);
        assertNotNull(alipayStrategy);
        assertEquals(PaymentChannel.ALIPAY, alipayStrategy.getChannel());
    }

    @Test
    public void testWeChatPayPreOrderCreation() {
        WeChatPayStrategy strategy = new WeChatPayStrategy();
        User user = new User();
        user.setId("test_user_001");

        PayOrder order = new PayOrder();
        order.setId("ORD_TEST_001");
        order.setAmount(new BigDecimal("99.00"));
        order.setChannel(PaymentChannel.WECHAT);

        PayPreOrderVo preOrderVo = strategy.createPreOrder(user, order);
        assertNotNull(preOrderVo);
        assertEquals("ORD_TEST_001", preOrderVo.getOrderId());
        assertEquals(PaymentChannel.WECHAT, preOrderVo.getChannel());
        assertNotNull(preOrderVo.getPayParams());
        assertEquals("wx_dummy_appid", preOrderVo.getPayParams().get("appid"));
    }

    @Test
    public void testUserVipExpireEffectiveCheck() {
        UserBo userBo = new UserBo();
        User user = new User();
        
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.DAY_OF_MONTH, 10);
        user.setVipExpireDate(cal.getTime());

        boolean isEffective = userBo.isPremiumEffective(user, new Date());
        assertTrue(isEffective);

        // 已过期的 VIP
        cal = Calendar.getInstance();
        cal.add(Calendar.DAY_OF_MONTH, -5);
        user.setVipExpireDate(cal.getTime());

        isEffective = userBo.isPremiumEffective(user, new Date());
        assertFalse(isEffective);
    }
}
