package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import org.junit.jupiter.api.Test;

public class DictWordBoTest {

    @Test
    public void testEmptyAndNullSeqList() {
        assertNull(DictWordBo.checkWordSeqsOrder(null), "null 列表应当合法");
        assertNull(DictWordBo.checkWordSeqsOrder(Collections.emptyList()), "空词书应当合法");
    }

    @Test
    public void testDenseSequentialList() {
        List<Integer> denseSeqs = Arrays.asList(1, 2, 3, 4, 5);
        assertNull(DictWordBo.checkWordSeqsOrder(denseSeqs), "标准稠密连续序号必须合法");
    }

    @Test
    public void testSparseSequentialWithGaps() {
        // 模拟用户在词书中间删除了单词，产生空洞
        List<Integer> sparseSeqs = Arrays.asList(1, 3, 7, 20, 1056);
        assertNull(DictWordBo.checkWordSeqsOrder(sparseSeqs), 
                "稀疏保序：中间删除产生的自然空洞应当完全合法，不再误报 DICT_WORD_ORDER_INVALID");
    }

    @Test
    public void testSparseSequentialWithHeadGaps() {
        // 模拟用户在词书头部删除了前 25 个单词，从 26 开始
        List<Integer> headGapSeqs = Arrays.asList(26, 27, 28, 50);
        assertNull(DictWordBo.checkWordSeqsOrder(headGapSeqs), 
                "稀疏保序：头部删除产生的起始空洞应当完全合法");
    }

    @Test
    public void testIllegalNonPositiveSeq() {
        // 异常防御：序号 <= 0 依然拦截
        List<Integer> illegalZero = Arrays.asList(0, 1, 2);
        String issue0 = DictWordBo.checkWordSeqsOrder(illegalZero);
        assertNotNull(issue0, "序号为0必须被识别为非法");
        assertTrue(issue0.contains("序号必须大于0"));

        List<Integer> illegalNegative = Arrays.asList(1, -5, 10);
        String issueNeg = DictWordBo.checkWordSeqsOrder(illegalNegative);
        assertNotNull(issueNeg, "序号为负数必须被识别为非法");
        assertTrue(issueNeg.contains("序号必须大于0"));
    }
}
