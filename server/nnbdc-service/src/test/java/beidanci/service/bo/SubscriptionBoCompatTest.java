package beidanci.service.bo;

import java.util.Calendar;
import java.util.Date;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

import beidanci.service.po.User;

public class SubscriptionBoCompatTest {

    @Test
    public void testLegacyIosSubscriptionStillEffective() {
        UserBo userBo = new UserBo();
        User user = new User();

        // 设置传统 iOS 订阅数据 (未使用通用 vipExpireDate)
        user.setIsPremiumIos(true);
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.DAY_OF_MONTH, 30);
        user.setSubscriptionExpireDateIos(cal.getTime());
        user.setSubscriptionStatusIos("active");

        // 验证 isPremiumEffective 依然返回 true，无损兼容 iOS
        boolean isEffective = userBo.isPremiumEffective(user, new Date());
        assertTrue(isEffective, "传统 iOS 订阅用户必须被正常识别为有效会员");
    }

    @Test
    public void testExpiredLegacyIosSubscription() {
        UserBo userBo = new UserBo();
        User user = new User();

        // 设为已过期的传统 iOS 订阅
        user.setIsPremiumIos(true);
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.DAY_OF_MONTH, -10);
        user.setSubscriptionExpireDateIos(cal.getTime());

        boolean isEffective = userBo.isPremiumEffective(user, new Date());
        assertFalse(isEffective, "已过期的传统 iOS 订阅不应判定为会员");
    }
}
