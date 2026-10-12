package beidanci.service.socket.system.game.russia;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 大厅用词抽样规则测试：词少的厅全量、词多的厅每天抽一批、同一天结果固定、跨天换一批。
 * 纯逻辑测试，不依赖 Spring 上下文和数据库。
 */
public class HallWordSamplerTest {

    private static List<String> wordIds(int count) {
        List<String> ids = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            ids.add("w" + i);
        }
        return ids;
    }

    @Test
    @DisplayName("词数不足 2000 的大厅全都要，一个都不少")
    void smallHallUsesAllWords() {
        for (int size : new int[]{471, 1512, 2000}) {
            List<String> all = wordIds(size);
            List<String> picked = HallWordSampler.pickWordIds(all, LocalDate.of(2026, 10, 12), "hall-1");

            assertEquals(size, picked.size(), "词数 " + size + " 的厅应当全都要");
            assertEquals(new HashSet<>(all), new HashSet<>(picked), "词数 " + size + " 的厅不该丢词");
        }
    }

    @Test
    @DisplayName("词数超过 2000 的大厅每天只取 2000 个，且互不重复、都来自本厅")
    void bigHallSamplesDailySize() {
        for (int size : new int[]{2001, 16290, 69752}) {
            List<String> all = wordIds(size);
            List<String> picked = HallWordSampler.pickWordIds(all, LocalDate.of(2026, 10, 12), "hall-1");

            assertEquals(2000, picked.size(), "词数 " + size + " 的厅应当只取 2000 个");
            assertEquals(2000, new HashSet<>(picked).size(), "抽出来的词不该有重复");
            assertTrue(new HashSet<>(all).containsAll(picked), "抽出来的词都必须来自本厅");
        }
    }

    @Test
    @DisplayName("同一天、同一个大厅，任何实例上算出来都一样")
    void sameDaySameHallIsStable() {
        List<String> first = HallWordSampler.pickWordIds(wordIds(69752), LocalDate.of(2026, 10, 12), "hall-1");
        List<String> second = HallWordSampler.pickWordIds(wordIds(69752), LocalDate.of(2026, 10, 12), "hall-1");
        assertEquals(first, second);
    }

    @Test
    @DisplayName("换一天就换一批")
    void nextDayGivesAnotherBatch() {
        List<String> today = HallWordSampler.pickWordIds(wordIds(69752), LocalDate.of(2026, 10, 12), "hall-1");
        List<String> tomorrow = HallWordSampler.pickWordIds(wordIds(69752), LocalDate.of(2026, 10, 13), "hall-1");

        assertNotEquals(today, tomorrow);
        HashSet<String> todaySet = new HashSet<>(today);
        long overlap = tomorrow.stream().filter(todaySet::contains).count();
        assertTrue(overlap < 2000, "两天的池子不该完全重合");
    }

    @Test
    @DisplayName("同一天的不同大厅各抽各的")
    void differentHallsSampleDifferently() {
        List<String> hallOne = HallWordSampler.pickWordIds(wordIds(69752), LocalDate.of(2026, 10, 12), "hall-1");
        List<String> hallTwo = HallWordSampler.pickWordIds(wordIds(69752), LocalDate.of(2026, 10, 12), "hall-2");
        assertNotEquals(hallOne, hallTwo);
    }
}
