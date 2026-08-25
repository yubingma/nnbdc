package beidanci.service.bo;

import java.util.Date;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

import beidanci.api.model.Badge;
import beidanci.api.model.BadgeVo;
import beidanci.api.model.UserBadgeVo;
import beidanci.service.po.UserBadge;

public class BadgeBoTest {

    @Test
    public void testBadgeEnumDefinitions() {
        assertEquals(16, Badge.values().length);

        Badge streak3 = Badge.STREAK_3;
        assertEquals("萌芽初醒", streak3.getDisplayName());
        assertEquals("HABIT", streak3.getCategory());
        assertEquals("BRONZE", streak3.getTier());
        assertEquals("STREAK_DAYS", streak3.getConditionType());
        assertEquals(3, streak3.getTargetValue());
        assertEquals(50, streak3.getRewardBubbles());
        assertFalse(streak3.isStackable());

        Badge flow = Badge.EASY_FLOW;
        assertEquals("极速心流", flow.getDisplayName());
        assertEquals("MASTERY", flow.getCategory());
        assertEquals("SILVER", flow.getTier());
        assertTrue(flow.isStackable());
        assertEquals(30, flow.getTargetValue());

        BadgeVo vo = BadgeVo.fromBadge(streak3);
        assertNotNull(vo);
        assertEquals("STREAK_3", vo.getCode());
        assertEquals("萌芽初醒", vo.getName());
    }

    @Test
    public void testStarLevelProgression() {
        assertEquals(1, computeStar(1));
        assertEquals(1, computeStar(9));
        assertEquals(2, computeStar(10));
        assertEquals(2, computeStar(29));
        assertEquals(3, computeStar(30));
        assertEquals(3, computeStar(59));
        assertEquals(4, computeStar(60));
        assertEquals(4, computeStar(99));
        assertEquals(5, computeStar(100));
        assertEquals(5, computeStar(999));
    }

    @Test
    public void testUserBadgeVoProgressComputation() {
        UserBadgeVo vo = new UserBadgeVo();
        vo.setIsUnlocked(false);
        vo.setProgressCurrent(14);
        vo.setProgressTarget(21);
        double percent = (double) vo.getProgressCurrent() / vo.getProgressTarget();
        vo.setProgressPercent(percent);

        assertFalse(vo.getIsUnlocked());
        assertEquals(Integer.valueOf(14), vo.getProgressCurrent());
        assertEquals(Integer.valueOf(21), vo.getProgressTarget());
        assertEquals(0.6666, vo.getProgressPercent(), 0.001);
    }

    @Test
    public void testStackableBadgeEntity() {
        UserBadge ub = new UserBadge();
        ub.setId(UUID.randomUUID().toString().replace("-", ""));
        ub.setUserId("user_001");
        ub.setBadgeCode(Badge.PERFECT_SCORE.name());
        ub.setObtainCount(12);
        ub.setStarLevel(2);
        ub.setUnlockedAt(new Date());
        ub.setIsEquipped(true);

        assertEquals("PERFECT_SCORE", ub.getBadgeCode());
        assertEquals(Integer.valueOf(12), ub.getObtainCount());
        assertEquals(Integer.valueOf(2), ub.getStarLevel());
        assertTrue(ub.getIsEquipped());
    }

    private int computeStar(int count) {
        if (count >= 100) return 5;
        if (count >= 60) return 4;
        if (count >= 30) return 3;
        if (count >= 10) return 2;
        return 1;
    }
}
