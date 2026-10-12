package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Arrays;
import java.util.List;

import org.junit.jupiter.api.Test;

import beidanci.service.po.MeaningItem;

public class MeaningItemBoPopularityTest {

    @Test
    public void testNormalizeSingleMeaning() {
        MeaningItem item = new MeaningItem();
        item.setPopularity(5);
        item.setPopularityPercent(20);

        MeaningItemBo.normalizePopularities(Arrays.asList(item));

        assertEquals(1, item.getPopularity());
        assertEquals(100, item.getPopularityPercent());
    }

    @Test
    public void testNormalizeTwoMeanings() {
        MeaningItem item1 = new MeaningItem();
        MeaningItem item2 = new MeaningItem();

        MeaningItemBo.normalizePopularities(Arrays.asList(item1, item2));

        assertEquals(1, item1.getPopularity());
        assertEquals(80, item1.getPopularityPercent());

        assertEquals(2, item2.getPopularity());
        assertEquals(20, item2.getPopularityPercent());
    }

    @Test
    public void testNormalizeThreeMeanings() {
        MeaningItem item1 = new MeaningItem();
        MeaningItem item2 = new MeaningItem();
        MeaningItem item3 = new MeaningItem();

        MeaningItemBo.normalizePopularities(Arrays.asList(item1, item2, item3));

        assertEquals(1, item1.getPopularity());
        assertEquals(75, item1.getPopularityPercent());

        assertEquals(2, item2.getPopularity());
        assertEquals(20, item2.getPopularityPercent());

        assertEquals(3, item3.getPopularity());
        assertEquals(5, item3.getPopularityPercent());
    }

    @Test
    public void testNormalizeFourMeanings() {
        MeaningItem item1 = new MeaningItem();
        MeaningItem item2 = new MeaningItem();
        MeaningItem item3 = new MeaningItem();
        MeaningItem item4 = new MeaningItem();

        List<MeaningItem> list = Arrays.asList(item1, item2, item3, item4);
        MeaningItemBo.normalizePopularities(list);

        for (int i = 0; i < list.size(); i++) {
            assertEquals(i + 1, list.get(i).getPopularity());
            assertNotNull(list.get(i).getPopularityPercent());
            assertTrue(list.get(i).getPopularityPercent() > 0);
        }
        assertEquals(70, item1.getPopularityPercent());
        assertEquals(18, item2.getPopularityPercent());
        assertEquals(8, item3.getPopularityPercent());
        assertEquals(4, item4.getPopularityPercent());
    }

    @Test
    public void testPreserveExistingValidPercentages() {
        MeaningItem item1 = new MeaningItem();
        item1.setPopularityPercent(60);
        item1.setPopularity(0);

        MeaningItem item2 = new MeaningItem();
        item2.setPopularityPercent(35);
        item2.setPopularity(0);

        List<MeaningItem> list = Arrays.asList(item1, item2);
        MeaningItemBo.normalizePopularities(list);

        // 原百分比总和为 95 (>= 90 && <= 100)，应当保留原有百分比，仅将 popularity 校准为递增
        assertEquals(60, item1.getPopularityPercent());
        assertEquals(1, item1.getPopularity());

        assertEquals(35, item2.getPopularityPercent());
        assertEquals(2, item2.getPopularity());
    }

    @Test
    public void testResolveParallelPopularities() {
        // 验证关键漏洞修复：哪怕原项都是并列 popularity=1，归一化后也必须消除并列，严格赋为 1, 2, 3
        MeaningItem item1 = new MeaningItem();
        item1.setPopularityPercent(60);
        item1.setPopularity(1);

        MeaningItem item2 = new MeaningItem();
        item2.setPopularityPercent(30);
        item2.setPopularity(1);

        MeaningItem item3 = new MeaningItem();
        item3.setPopularityPercent(10);
        item3.setPopularity(1);

        List<MeaningItem> list = Arrays.asList(item1, item2, item3);
        MeaningItemBo.normalizePopularities(list);

        assertEquals(1, item1.getPopularity());
        assertEquals(2, item2.getPopularity());
        assertEquals(3, item3.getPopularity());
    }

    @Test
    public void testNormalizeDto() {
        beidanci.api.model.MeaningItemDto dto1 = new beidanci.api.model.MeaningItemDto();
        beidanci.api.model.MeaningItemDto dto2 = new beidanci.api.model.MeaningItemDto();

        List<beidanci.api.model.MeaningItemDto> dtos = Arrays.asList(dto1, dto2);
        MeaningItemBo.normalizeDtoPopularities(dtos);

        assertEquals(1, dto1.getPopularity());
        assertEquals(80, dto1.getPopularityPercent());
        assertEquals(2, dto2.getPopularity());
        assertEquals(20, dto2.getPopularityPercent());
    }

    @Test
    public void testNormalizeKeepsListOrder() {
        // 归一化只写回热度与百分比，绝不重排传入列表：
        // 词书导入依赖该顺序与 AI 返回的义项一一对应，重排会让释义配上别人的例句与同义词。
        MeaningItem lowPct = new MeaningItem();
        lowPct.setPopularityPercent(10);

        MeaningItem highPct = new MeaningItem();
        highPct.setPopularityPercent(60);

        MeaningItem midPct = new MeaningItem();
        midPct.setPopularityPercent(30);

        List<MeaningItem> list = Arrays.asList(lowPct, highPct, midPct);
        MeaningItemBo.normalizePopularities(list);

        assertSame(lowPct, list.get(0));
        assertSame(highPct, list.get(1));
        assertSame(midPct, list.get(2));

        assertEquals(3, lowPct.getPopularity());
        assertEquals(1, highPct.getPopularity());
        assertEquals(2, midPct.getPopularity());

        assertEquals(10, lowPct.getPopularityPercent());
        assertEquals(60, highPct.getPopularityPercent());
        assertEquals(30, midPct.getPopularityPercent());
    }

    @Test
    public void testNormalizeFallsBackToPopularityWhenPercentMissing() {
        // 百分比整体缺位时，必须按 AI 判定的热度排先后，而不是按 AI 返回数组的先后
        MeaningItem third = new MeaningItem();
        third.setPopularity(3);

        MeaningItem first = new MeaningItem();
        first.setPopularity(1);

        MeaningItem second = new MeaningItem();
        second.setPopularity(2);

        List<MeaningItem> list = Arrays.asList(third, first, second);
        MeaningItemBo.normalizePopularities(list);

        assertEquals(1, first.getPopularity());
        assertEquals(2, second.getPopularity());
        assertEquals(3, third.getPopularity());

        assertEquals(75, first.getPopularityPercent());
        assertEquals(20, second.getPopularityPercent());
        assertEquals(5, third.getPopularityPercent());
    }
}
