package beidanci.service.socket.system.game.russia;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

/**
 * 机器人"还想不想再开一局"的概率。
 *
 * <p>线上体感：同一个人连赢十把，机器人一局接一局地陪打，从不走人——
 * 因为离开概率只看随机，和输赢完全无关。规则改成：连输会烦、连赢也会腻。
 * 基础 5%；每多输一局 +15%，每多赢一局 +8%，封顶 60%。
 */
public class BotLeaveChanceTest {

    @Test
    public void testFreshBotRarelyLeaves() {
        assertEquals(0.05, RussiaRoom.botLeaveChanceAfterStreak(0, 0), 1e-9);
    }

    @Test
    public void testLeavesMoreOftenAfterConsecutiveLosses() {
        assertEquals(0.20, RussiaRoom.botLeaveChanceAfterStreak(1, 0), 1e-9);
        assertEquals(0.35, RussiaRoom.botLeaveChanceAfterStreak(2, 0), 1e-9);
        assertEquals(0.50, RussiaRoom.botLeaveChanceAfterStreak(3, 0), 1e-9);
    }

    @Test
    public void testAlsoGetsBoredAfterConsecutiveWins() {
        assertEquals(0.13, RussiaRoom.botLeaveChanceAfterStreak(0, 1), 1e-9);
        assertEquals(0.21, RussiaRoom.botLeaveChanceAfterStreak(0, 2), 1e-9);
        assertEquals(0.37, RussiaRoom.botLeaveChanceAfterStreak(0, 4), 1e-9);
    }

    @Test
    public void testLossesPushHarderThanWins() {
        // 同样 3 局，连输比连赢更想走
        assertEquals(true, RussiaRoom.botLeaveChanceAfterStreak(3, 0) > RussiaRoom.botLeaveChanceAfterStreak(0, 3));
    }

    @Test
    public void testChanceIsCapped() {
        assertEquals(0.60, RussiaRoom.botLeaveChanceAfterStreak(4, 0), 1e-9);
        assertEquals(0.60, RussiaRoom.botLeaveChanceAfterStreak(0, 7), 1e-9);
        assertEquals(0.60, RussiaRoom.botLeaveChanceAfterStreak(30, 30), 1e-9);
    }

    @Test
    public void testNegativeStreakIsTreatedAsZero() {
        assertEquals(0.05, RussiaRoom.botLeaveChanceAfterStreak(-3, -2), 1e-9);
    }
}
