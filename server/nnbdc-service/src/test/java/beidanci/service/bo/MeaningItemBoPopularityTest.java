package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.ArrayList;
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
}
