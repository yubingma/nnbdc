package beidanci.service.bo;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

import beidanci.api.model.MsgType;
import beidanci.service.po.Msg;
import beidanci.service.po.PromoActivity;
import beidanci.service.po.User;

public class MsgBoAdviceRedeemTest {

    private MsgBo msgBo;
    private List<Msg> createdMsgs;
    private User testUser;
    private User sysUser;

    @BeforeEach
    public void setUp() throws Exception {
        createdMsgs = new ArrayList<>();
        testUser = new User();
        testUser.setId("user_123");
        testUser.setNickName("TestUser");

        sysUser = new User();
        sysUser.setId("sys_user");
        sysUser.setNickName("System");

        msgBo = new MsgBo() {
            @Override
            public void createMsg(String content, MsgType msgType, String clientType, User fromUser, User toUser) {
                Msg msg = new Msg(msgType);
                msg.setContent(content);
                msg.setFromUser(fromUser);
                msg.setToUser(toUser);
                createdMsgs.add(msg);
            }

            @Override
            public void replyAdvice(String content, User toUser, UserBo userBo) {
                createMsg(content, MsgType.AdviceReply, null, sysUser, toUser);
            }
        };

        UserBo mockUserBo = new UserBo() {
            @Override
            public User getSysUser_sys(boolean force) {
                return sysUser;
            }
        };

        Field userBoField = MsgBo.class.getDeclaredField("userBo");
        userBoField.setAccessible(true);
        userBoField.set(msgBo, mockUserBo);
    }

    @Test
    public void testSendAdviceWithValidPromoCode() throws Exception {
        PromoActivity activeActivity = new PromoActivity();
        activeActivity.setId("act_001");
        activeActivity.setName("测试赠送VIP");
        activeActivity.setActivityCode("VIP888");
        activeActivity.setDuration("30天");
        activeActivity.setIsActive(true);
        activeActivity.setMaxRedemptions(100);
        activeActivity.setRedemptionCount(0);

        PromoActivityBo mockPromoActivityBo = new PromoActivityBo() {
            @Override
            public PromoActivity findByCode(String code) {
                if ("VIP888".equals(code)) {
                    return activeActivity;
                }
                return null;
            }
        };

        PromoRedemptionBo mockPromoRedemptionBo = new PromoRedemptionBo() {
            @Override
            public boolean hasRedeemed(String userId, String activityId) {
                return false;
            }

            @Override
            public User redeem(User user, PromoActivity activity) {
                user.setPremiumOverrideEnabled(true);
                return user;
            }
        };

        Field activityBoField = MsgBo.class.getDeclaredField("promoActivityBo");
        activityBoField.setAccessible(true);
        activityBoField.set(msgBo, mockPromoActivityBo);

        Field redemptionBoField = MsgBo.class.getDeclaredField("promoRedemptionBo");
        redemptionBoField.setAccessible(true);
        redemptionBoField.set(msgBo, mockPromoRedemptionBo);

        // 测试输入带首尾空格的兑换码
        User updated = msgBo.sendAdvice("  VIP888  ", "FLUTTER_ANDROID", testUser);

        assertNotNull(updated);
        assertTrue(Boolean.TRUE.equals(updated.getPremiumOverrideEnabled()));
        assertEquals(2, createdMsgs.size());
        assertEquals(MsgType.Advice, createdMsgs.get(0).getMsgType());
        assertEquals("  VIP888  ", createdMsgs.get(0).getContent());

        assertEquals(MsgType.AdviceReply, createdMsgs.get(1).getMsgType());
        assertTrue(createdMsgs.get(1).getContent().contains("恭喜您！已成功兑换【测试赠送VIP】"));
        assertTrue(createdMsgs.get(1).getContent().contains("30天"));
    }

    @Test
    public void testSendAdviceWithAlreadyRedeemedCode() throws Exception {
        PromoActivity activeActivity = new PromoActivity();
        activeActivity.setId("act_002");
        activeActivity.setName("老用户活动");
        activeActivity.setActivityCode("USED123");
        activeActivity.setIsActive(true);

        PromoActivityBo mockPromoActivityBo = new PromoActivityBo() {
            @Override
            public PromoActivity findByCode(String code) {
                if ("USED123".equals(code)) {
                    return activeActivity;
                }
                return null;
            }
        };

        PromoRedemptionBo mockPromoRedemptionBo = new PromoRedemptionBo() {
            @Override
            public boolean hasRedeemed(String userId, String activityId) {
                return true; // 已兑换过
            }
        };

        Field activityBoField = MsgBo.class.getDeclaredField("promoActivityBo");
        activityBoField.setAccessible(true);
        activityBoField.set(msgBo, mockPromoActivityBo);

        Field redemptionBoField = MsgBo.class.getDeclaredField("promoRedemptionBo");
        redemptionBoField.setAccessible(true);
        redemptionBoField.set(msgBo, mockPromoRedemptionBo);

        msgBo.sendAdvice("USED123", "FLUTTER_IOS", testUser);

        assertEquals(2, createdMsgs.size());
        assertEquals(MsgType.AdviceReply, createdMsgs.get(1).getMsgType());
        assertTrue(createdMsgs.get(1).getContent().contains("您已兑换过该活动码，不能重复兑换"));
    }

    @Test
    public void testSendAdviceWithExpiredPromoCode() throws Exception {
        PromoActivity expiredActivity = new PromoActivity();
        expiredActivity.setId("act_003");
        expiredActivity.setName("过期活动");
        expiredActivity.setActivityCode("EXPIRED");
        expiredActivity.setIsActive(true);
        expiredActivity.setEndTime(new Date(System.currentTimeMillis() - 100000)); // 已结束

        PromoActivityBo mockPromoActivityBo = new PromoActivityBo() {
            @Override
            public PromoActivity findByCode(String code) {
                if ("EXPIRED".equals(code)) {
                    return expiredActivity;
                }
                return null;
            }
        };

        Field activityBoField = MsgBo.class.getDeclaredField("promoActivityBo");
        activityBoField.setAccessible(true);
        activityBoField.set(msgBo, mockPromoActivityBo);

        Field redemptionBoField = MsgBo.class.getDeclaredField("promoRedemptionBo");
        redemptionBoField.setAccessible(true);
        redemptionBoField.set(msgBo, new PromoRedemptionBo());

        msgBo.sendAdvice("EXPIRED", "FLUTTER_IOS", testUser);

        assertEquals(2, createdMsgs.size());
        assertEquals(MsgType.AdviceReply, createdMsgs.get(1).getMsgType());
        assertTrue(createdMsgs.get(1).getContent().contains("该活动已结束"));
    }
}
