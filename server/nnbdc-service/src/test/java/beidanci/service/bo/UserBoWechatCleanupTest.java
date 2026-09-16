package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

import beidanci.service.po.User;

/**
 * 微信授权信息清理规则测试：只清微信来源的数据，保留 openid/unionid 以及用户自己设置的昵称/头像。
 */
public class UserBoWechatCleanupTest {

    private static final String WECHAT_AVATAR = "https://thirdwx.qlogo.cn/mmopen/vi_32/ljyWJm1hffQiaibGujt1q9mzuxwZeXVfEAsC2BXwUicv0PjKklsTmTqCeGblzcThTqhp2GVBjl7I5doicneqd7vefWCFNZRWgu6b6xCUUPVslJQ/132";

    private static User wechatUser(String nickName, String wechatNickname, String wechatAvatar) {
        User user = new User();
        user.setId("29085be444c8417b93b7fea4a7dfec44");
        user.setUserName("wx_c0e0aa5f560947f3");
        user.setNickName(nickName);
        user.setWechatOpenId("olP_Y6xJBOCP-98LZlrG06JgoaBk");
        user.setWechatUnionId("oW-TY6_26T2nqKjOU7NDfmk27Cms");
        user.setWechatNickname(wechatNickname);
        user.setWechatAvatar(wechatAvatar);
        return user;
    }

    @Test
    public void testClearWechatNicknameAndAvatar() {
        User user = wechatUser("晴茉", "晴茉", WECHAT_AVATAR);

        assertTrue(UserBo.clearWechatProfileOf(user));

        assertNull(user.getNickName());
        assertNull(user.getWechatNickname());
        assertNull(user.getWechatAvatar());
        // 标识符保留，用户仍然可以微信登录回原账号
        assertEquals("olP_Y6xJBOCP-98LZlrG06JgoaBk", user.getWechatOpenId());
        assertEquals("oW-TY6_26T2nqKjOU7NDfmk27Cms", user.getWechatUnionId());
    }

    @Test
    public void testKeepNickNameEditedByUser() {
        User user = wechatUser("背单词的小王", "晴茉", WECHAT_AVATAR);

        assertTrue(UserBo.clearWechatProfileOf(user));

        assertEquals("背单词的小王", user.getNickName());
        assertNull(user.getWechatNickname());
    }

    @Test
    public void testClearNickNameFilteredFromWechatNickname() {
        // 注册写 nick_name 时做过 emoji 过滤，过滤后的形态也要认出来
        User user = wechatUser("晴茉", "晴茉😀", null);

        assertTrue(UserBo.clearWechatProfileOf(user));

        assertNull(user.getNickName());
        assertNull(user.getWechatNickname());
    }

    @Test
    public void testKeepAvatarSetByUser() {
        User user = wechatUser("晴茉", "晴茉", "https://back.nnbdc.com/img/avatar/abc.png");

        assertTrue(UserBo.clearWechatProfileOf(user));

        assertEquals("https://back.nnbdc.com/img/avatar/abc.png", user.getWechatAvatar());
    }

    @Test
    public void testAlreadyClearedUserIsNoop() {
        User user = wechatUser(null, null, null);
        assertFalse(UserBo.clearWechatProfileOf(user));
    }

    @Test
    public void testIsWechatAvatarUrl() {
        assertTrue(UserBo.isWechatAvatarUrl(WECHAT_AVATAR));
        assertTrue(UserBo.isWechatAvatarUrl("http://wx.qlogo.cn/mmopen/xxx"));
        assertTrue(UserBo.isWechatAvatarUrl("https://qlogo.cn/x"));
        assertFalse(UserBo.isWechatAvatarUrl("https://back.nnbdc.com/img/avatar/abc.png"));
        // 形似微信域名但不是的地址不能被误判
        assertFalse(UserBo.isWechatAvatarUrl("https://qlogo.cn.evil.com/x"));
        assertFalse(UserBo.isWechatAvatarUrl("data:image/png;base64,AAAA"));
        assertFalse(UserBo.isWechatAvatarUrl(null));
        assertFalse(UserBo.isWechatAvatarUrl(""));
    }
}
