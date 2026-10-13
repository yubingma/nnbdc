package beidanci.service.socket.system.game.russia.state;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

/**
 * 连对奖励的道具配比：水雷 2/3、海星 1/3。
 *
 * 产品要求按 1:2（海星:水雷）分配，命中区间不能含糊——三个等概率骰子里
 * 两个给水雷、一个给海星，多一个少一个都是配比错了。
 */
public class RewardPropsOddsTest {

    @Test
    public void twoOfThreeDiceGiveWaterMine() {
        assertEquals(0, GetNextWordProcessor.rollRewardProps(0), "骰子 0 应给水雷");
        assertEquals(0, GetNextWordProcessor.rollRewardProps(1), "骰子 1 应给水雷");
    }

    @Test
    public void oneOfThreeDiceGivesStarfish() {
        assertEquals(1, GetNextWordProcessor.rollRewardProps(2), "骰子 2 应给海星");
    }
}
