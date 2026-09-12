package beidanci.service.util;

import java.util.List;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

public class UtilMeaningTest {

    @Test
    public void testSplitByChineseSemicolon() {
        assertEquals(List.of("神的", "神圣的"), Util.splitMeanings("神的；神圣的"));
    }

    @Test
    public void testSplitByEnglishSemicolon() {
        assertEquals(List.of("而且", "不但如此"), Util.splitMeanings("而且; 不但如此"));
    }

    @Test
    public void testSplitThreeParts() {
        assertEquals(List.of("动态", "活力", "动力"), Util.splitMeanings("动态；活力；动力"));
    }

    @Test
    public void testCommaIsNotASeparator() {
        // 近义表达用逗号连接属于合法写法，必须保持为一条
        assertEquals(List.of("有，拥有"), Util.splitMeanings("有，拥有"));
        assertEquals(List.of("有, 拥有"), Util.splitMeanings("有, 拥有"));
    }

    @Test
    public void testBlankPartsAndDuplicatesAreDropped() {
        assertEquals(List.of("砖", "砖块"), Util.splitMeanings("砖；； 砖 ；砖块"));
    }

    @Test
    public void testTrailingCommaIsStrippedPerPart() {
        assertEquals(List.of("惯用的", "节约使用的"), Util.splitMeanings("惯用的，；节约使用的"));
    }

    @Test
    public void testNullAndBlankYieldEmptyList() {
        assertTrue(Util.splitMeanings(null).isEmpty());
        assertTrue(Util.splitMeanings("   ").isEmpty());
    }

    @Test
    public void testHasMeaningSeparator() {
        assertTrue(Util.hasMeaningSeparator("神的；神圣的"));
        assertTrue(Util.hasMeaningSeparator("而且; 不但如此"));
        assertFalse(Util.hasMeaningSeparator("有，拥有"));
        assertFalse(Util.hasMeaningSeparator(null));
    }
}
