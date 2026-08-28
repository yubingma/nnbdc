package beidanci.service.controller;

import java.lang.reflect.Field;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

import beidanci.api.Result;
import beidanci.service.bo.MsgBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.User;

public class MsgControllerDeleteMsgTest {

    private MsgController msgController;
    private User regularUser;
    private User adminUser;
    private String deletedMsgId;

    @BeforeEach
    public void setUp() throws Exception {
        msgController = new MsgController();
        deletedMsgId = null;

        regularUser = new User();
        regularUser.setId("user_normal");
        regularUser.setIsAdmin(false);

        adminUser = new User();
        adminUser.setId("user_admin");
        adminUser.setIsAdmin(true);

        UserBo mockUserBo = new UserBo() {
            @Override
            public User findById(java.io.Serializable id, boolean newSession) {
                if ("user_admin".equals(id)) {
                    return adminUser;
                } else if ("user_normal".equals(id)) {
                    return regularUser;
                }
                return null;
            }
        };

        MsgBo mockMsgBo = new MsgBo() {
            @Override
            public void deleteMsg(String msgId) {
                deletedMsgId = msgId;
            }
        };

        Field userBoField = MsgController.class.getDeclaredField("userBo");
        userBoField.setAccessible(true);
        userBoField.set(msgController, mockUserBo);

        Field msgBoField = MsgController.class.getDeclaredField("msgBo");
        msgBoField.setAccessible(true);
        msgBoField.set(msgController, mockMsgBo);
    }

    @Test
    public void testDeleteMsgByAdminSuccess() {
        Result<Void> result = msgController.deleteMsg("msg_999", "user_admin");
        assertTrue(result.isSuccess());
        assertEquals("msg_999", deletedMsgId);
    }

    @Test
    public void testDeleteMsgByNonAdminForbidden() {
        Result<Void> result = msgController.deleteMsg("msg_999", "user_normal");
        assertFalse(result.isSuccess());
        assertEquals("管理员权限不足", result.getMsg());
        assertNull(deletedMsgId);
    }

    @Test
    public void testDeleteMsgByNonExistentUserForbidden() {
        Result<Void> result = msgController.deleteMsg("msg_999", "user_unknown");
        assertFalse(result.isSuccess());
        assertEquals("管理员权限不足", result.getMsg());
        assertNull(deletedMsgId);
    }
}
