package beidanci.service.socket.system.game.russia;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

/**
 * 机器人连败后"不想再来一局"的概率。
 *
 * <p>线上体感：同一个人连赢十把，机器人一局接一局地陪打，从不走人——
 * 因为离开概率只看"随机"，和输赢完全无关。这里的规则：
 * 0 连败 5%，每多输一局 +15%，封顶 60%。
 */
public class BotLeaveChanceTest {

    @Test
    public void testFreshBotRarelyLeaves() {
        assertEquals(0.05, RussiaRoom.botLeaveChanceAfterLosses(0), 1e-9);
    }

    @Test
    public void testLeavesMoreOftenAfterConsecutiveLosses() {
        assertEquals(0.20, RussiaRoom.botLeaveChanceAfterLosses(1), 1e-9);
        assertEquals(0.35, RussiaRoom.botLeaveChanceAfterLosses(2), 1e-9);
        assertEquals(0.50, RussiaRoom.botLeaveChanceAfterLosses(3), 1e-9);
    }

    @Test
    public void testChanceIsCapped() {
        assertEquals(0.60, RussiaRoom.botLeaveChanceAfterLosses(4), 1e-9);
        assertEquals(0.60, RussiaRoom.botLeaveChanceAfterLosses(30), 1e-9);
    }

    @Test
    public void testNegativeStreakIsTreatedAsZero() {
        assertEquals(0.05, RussiaRoom.botLeaveChanceAfterLosses(-3), 1e-9);
    }
}
