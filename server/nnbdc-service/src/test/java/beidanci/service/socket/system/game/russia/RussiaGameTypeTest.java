package beidanci.service.socket.system.game.russia;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;

import java.lang.reflect.Method;

import org.junit.jupiter.api.Test;

import beidanci.api.model.UserVo;
import beidanci.service.socket.UserCmd;

/**
 * 游戏类型的两个硬约束：
 *
 * <p>一、入口指令尾部的 gameType 必须按长度判空。老客户端不会发这个参数，
 * 直接下标访问会让老包在进厅/开房/进房时抛 ArrayIndexOutOfBoundsException，
 * 而 socket 层把异常吞掉只打日志——用户看到的是"点了完全没反应"，连大厅都进不去。
 *
 * <p>二、房间只接纳完全相同的游戏类型（null 只与 null 相等）。
 * 两个游戏共用这套房间与对局逻辑，混池会配出"一个玩戳泡泡、一个玩消砖块"的对局。
 */
public class RussiaGameTypeTest {

    private String gameTypeOf(String[] args, int argIndex) throws Exception {
        UserCmd userCmd = new UserCmd();
        userCmd.setCmd("ENTER_GAME_HALL");
        userCmd.setArgs(args);
        Method method = Russia.class.getDeclaredMethod("gameTypeOf", UserVo.class, UserCmd.class, int.class);
        method.setAccessible(true);
        return (String) method.invoke(null, new UserVo(), userCmd, argIndex);
    }

    private RussiaRoom roomOf(String gameType) {
        return new RussiaRoom(null, mock(Hall.class), null, null, null, null, null, null, null, null, null,
                gameType);
    }

    @Test
    public void testOldClientWithoutGameTypeArg() throws Exception {
        // 老客户端：参数不够长 / 没带 / 带了个空白，都必须是"无类型"，绝不能抛异常
        assertNull(gameTypeOf(new String[] { "12", "" }, 2));
        assertNull(gameTypeOf(new String[] { "12" }, 1));
        assertNull(gameTypeOf(new String[] { "12", "34", "  " }, 2));
        assertNull(gameTypeOf(new String[] {}, 1));
        assertNull(gameTypeOf(null, 2));
    }

    @Test
    public void testNewClientGameTypeArg() throws Exception {
        assertEquals("brick", gameTypeOf(new String[] { "12", "34", "brick" }, 2));
        assertEquals("russia", gameTypeOf(new String[] { "12", "russia" }, 1));
    }

    @Test
    public void testRoomOnlyAcceptsSameGameType() {
        assertTrue(roomOf("brick").acceptsGameType("brick"));
        assertTrue(roomOf("russia").acceptsGameType("russia"));
        assertFalse(roomOf("brick").acceptsGameType("russia"));
        assertFalse(roomOf("russia").acceptsGameType("brick"));
    }

    @Test
    public void testLegacyRoomOnlyMatchesLegacyPlayer() {
        // 老客户端没有类型：只与同样没有类型的房间互配，绝不跨游戏
        assertTrue(roomOf(null).acceptsGameType(null));
        assertFalse(roomOf(null).acceptsGameType("brick"));
        assertFalse(roomOf("brick").acceptsGameType(null));

        // 进不去的时候要说清楚是"房主版本旧"，不能误报成"另一款游戏"
        assertTrue(roomOf(null).isLegacyGameType());
        assertFalse(roomOf("brick").isLegacyGameType());
    }
}
