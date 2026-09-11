package beidanci.service.socket.system.game.russia;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

import org.junit.jupiter.api.Test;

import beidanci.api.model.UserGameVo;
import beidanci.api.model.UserVo;

/**
 * 机器人虚构数据的测试：强度跟随玩家自身水平，且显示出来的“场次-胜率-积分”互相自洽。
 */
public class RussiaRoomBotTest {

    /**
     * 每局净得分尺度，见 GameOverProcessor.calculateWinerScoreAdjustment(0, 0)
     */
    private static final int PER_GAME_SCORE = 35;

    /**
     * 每局积分变动的上限（绝对值），用于校验积分能被场次解释
     */
    private static final int MAX_SCORE_PER_GAME = 60;

    private UserVo makeHuman(int winCount, int loseCount) {
        UserVo human = new UserVo();
        human.setCowDung(200);
        human.setGameScore(0);
        human.setUserGames(new ArrayList<>(List.of(new UserGameVo(null, winCount, loseCount, 0, "russia"))));
        return human;
    }

    /**
     * 通过反射调用私有的虚构数据逻辑（与 DataSanitizeBoTest 的做法一致，无需启动 Spring 容器）
     */
    private UserVo makeBotOf(UserVo human) throws Exception {
        RussiaRoom room = new RussiaRoom(null, null, null, null, null, null, null, null, null, null, null);
        UserVo bot = new UserVo();
        Method method = RussiaRoom.class.getDeclaredMethod("fillFakeUserData", UserVo.class, UserVo.class);
        method.setAccessible(true);
        method.invoke(room, bot, human);
        return bot;
    }

    private UserGameVo russiaGameOf(UserVo user) {
        for (UserGameVo game : user.getUserGames()) {
            if ("russia".equals(game.getGame())) {
                return game;
            }
        }
        throw new IllegalStateException("机器人没有 russia 战绩");
    }

    private int totalCountOf(UserVo bot) {
        UserGameVo game = russiaGameOf(bot);
        return game.getWinCount() + game.getLoseCount();
    }

    @Test
    public void testFakeDataIsSelfConsistent() throws Exception {
        // 覆盖新手、中等、人机双方各档玩家
        int[][] humans = { { 0, 0 }, { 70, 30 }, { 200, 200 }, { 20, 80 }, { 120, 80 } };
        for (int[] humanGames : humans) {
            for (int i = 0; i < 100; i++) {
                UserVo bot = makeBotOf(makeHuman(humanGames[0], humanGames[1]));
                UserGameVo game = russiaGameOf(bot);

                assertTrue(game.getWinCount() >= 0, "胜场不能为负");
                assertTrue(game.getLoseCount() >= 0, "负场不能为负");
                assertTrue(totalCountOf(bot) >= 20, "场次不应过少");

                // 积分由净胜场派生：净胜为正才有积分，且与净胜场同向
                int netWins = game.getWinCount() - game.getLoseCount();
                assertEquals(Math.max(0, netWins) * PER_GAME_SCORE, bot.getGameScore(),
                        "积分应与净胜场自洽");

                // 积分必须能被场次解释（每局最多 ±MAX_SCORE_PER_GAME 分）
                assertTrue(bot.getGameScore() <= MAX_SCORE_PER_GAME * totalCountOf(bot),
                        "积分超出场次所能解释的上限");
                assertTrue(bot.getCowDung() >= 0, "魔法泡泡不能为负");
            }
        }
    }

    @Test
    public void testStrengthFollowsHuman() throws Exception {
        // 玩家是高手 → 机器人胜率应偏高
        for (int i = 0; i < 200; i++) {
            assertTrue(winRatioOf(makeBotOf(makeHuman(70, 30))) >= 0.55, "机器人强度应跟随玩家水平（偏高）");
        }
        // 玩家是菜鸟 → 机器人胜率应偏低
        for (int i = 0; i < 200; i++) {
            assertTrue(winRatioOf(makeBotOf(makeHuman(20, 80))) <= 0.35, "机器人强度应跟随玩家水平（偏低）");
        }
        // 胜率上限：即使玩家全胜，也不会出现 100% 胜率这种一眼假的战绩
        for (int i = 0; i < 200; i++) {
            assertTrue(winRatioOf(makeBotOf(makeHuman(200, 0))) <= 0.88, "机器人胜率不应逼近 100%");
        }
    }

    @Test
    public void testNewPlayerGetsBalancedBot() throws Exception {
        // 没有战绩的新玩家：按五五开匹配，场次取下限
        for (int i = 0; i < 200; i++) {
            UserVo bot = makeBotOf(makeHuman(0, 0));
            double ratio = winRatioOf(bot);
            assertTrue(ratio >= 0.4 && ratio <= 0.6, "新手应匹配到五五开的机器人，实际=" + ratio);
            assertEquals(20, totalCountOf(bot), "无战绩玩家的对手场次应取下限");
        }
    }

    @Test
    public void testGameCountIsComparableToHuman() throws Exception {
        // 对手场次与玩家同量级（玩家场次的 0.6~1.4 倍），避免出现积分与玩家分段严重脱节的对手
        for (int i = 0; i < 200; i++) {
            int total = totalCountOf(makeBotOf(makeHuman(100, 100)));
            assertTrue(total >= 120 && total <= 280, "对手场次应与玩家同量级，实际=" + total);
        }
    }

    private double winRatioOf(UserVo bot) {
        UserGameVo game = russiaGameOf(bot);
        return (double) game.getWinCount() / (game.getWinCount() + game.getLoseCount());
    }
}
