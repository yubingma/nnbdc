package beidanci.service.socket.system.game.russia.state;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

/**
 * 局中人离开房间时该不该判战败（{@link ReadyState#shouldPunishLeaving}）。
 *
 * 背景：对局进行中点返回箭头或换房间，服务端原来什么都不做——走掉的人零代价，
 * 留下的对手则被扔在一个没有对手的界面里把血条打空，双方谁都不结算。
 * 现在由 RussiaRoom.userLeave 调 handleUserLeft 当场判负收场。
 *
 * 这里钉住的是"什么时候不许判"。
 */
public class ReadyStateUserLeftTest {

    @Test
    public void punishesLeavingInRealBattle() {
        assertTrue(ReadyState.shouldPunishLeaving(true, false, false), "正式对战中途走人必须判负");
    }

    @Test
    public void doesNotPunishWhenGameIsNotRunning() {
        assertFalse(ReadyState.shouldPunishLeaving(false, false, false), "还没开打或已经结算，没有胜负可判");
    }

    @Test
    public void doesNotPunishExerciserLeaving() {
        assertFalse(ReadyState.shouldPunishLeaving(true, true, false), "单人练习不计分，离开不判负");
    }

    @Test
    public void doesNotPunishWhenSomeoneElseIsExercising() {
        // 让"别人离开"占掉 gameOverProcessor 的 loser 位，练习者自己结束练习时判负会失效、练习卡死
        assertFalse(ReadyState.shouldPunishLeaving(true, false, true), "房间里有人在做练习时这一局不计分");
    }
}
