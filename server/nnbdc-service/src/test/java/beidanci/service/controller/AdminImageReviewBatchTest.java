package beidanci.service.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

import beidanci.api.model.WordImageDto;
import beidanci.service.bo.SysParamBo;
import beidanci.service.bo.WordBo;
import beidanci.service.bo.WordImageBo;
import beidanci.service.po.SysParam;
import beidanci.service.po.Word;
import beidanci.service.util.JsonUtils;

/**
 * 批量审图的并发送审测试。
 *
 * 送审改成一池线程并发跑之后，最容易坏的是"一张图被审两次"或"某张图被整段跳过"——
 * 前者会凭空多删一张配图，后者会让那张图永远没人审。这里用 100 张图（跨两个批次）钉住：
 * 每张恰好审一次、计数按批次正确累加、游标停在批次边界上。
 */
public class AdminImageReviewBatchTest {

    private static final int IMAGE_COUNT = 100;

    /** 与 AdminImageReviewController.REVIEW_BATCH_SIZE 对齐（16 路 × 4 = 64），100 张因此分两批 */
    private static final int FIRST_BATCH_SIZE = 64;

    private AdminImageReviewController controller;
    private WordBo wordBo;
    private WordImageBo wordImageBo;
    private SysParamBo sysParamBo;

    @BeforeEach
    public void setUp() throws Exception {
        controller = new AdminImageReviewController();
        wordBo = Mockito.mock(WordBo.class);
        wordImageBo = Mockito.mock(WordImageBo.class);
        sysParamBo = Mockito.mock(SysParamBo.class);
        inject(controller, "wordBo", wordBo);
        inject(controller, "wordImageBo", wordImageBo);
        inject(controller, "sysParamBo", sysParamBo);

        List<WordImageDto> images = new ArrayList<>();
        for (int i = 0; i < IMAGE_COUNT; i++) {
            WordImageDto dto = new WordImageDto();
            dto.setId(imageId(i));
            dto.setWordId("word-" + i);
            dto.setImageFile("word" + i + ".jpg");
            images.add(dto);
        }
        when(wordBo.getWordImagesOfDict("0")).thenReturn(images);

        Word word = new Word();
        word.setSpell("probe");
        when(wordBo.findById(any())).thenReturn(word);
        when(wordImageBo.reviewImageAndApply(any(), any(), any(), anyBoolean()))
                .thenAnswer(invocation -> verdictOf(invocation.getArgument(0)));
    }

    @Test
    public void testEveryImageReviewedExactlyOnce() throws Exception {
        review();

        ArgumentCaptor<String> idCaptor = ArgumentCaptor.forClass(String.class);
        verify(wordImageBo, times(IMAGE_COUNT)).reviewImageAndApply(idCaptor.capture(), any(), any(), anyBoolean());

        Set<String> expected = new HashSet<>();
        for (int i = 0; i < IMAGE_COUNT; i++) {
            expected.add(imageId(i));
        }
        // 并发送审去重之后仍应覆盖全部图：重复会多删图，遗漏会让图永远停在审核中
        assertEquals(expected, new HashSet<>(idCaptor.getAllValues()));
    }

    @Test
    public void testCountsAndCursorAdvanceByBatch() throws Exception {
        review();

        List<AdminImageReviewController.ReviewProgress> saved = savedProgress();

        // 第一批跑完先落一次游标，取的是本批最后一张的 id
        assertEquals(3, saved.size());
        assertEquals(imageId(FIRST_BATCH_SIZE - 1), saved.get(0).imageIdCursor);
        assertEquals(FIRST_BATCH_SIZE, saved.get(0).reviewedCount);

        // 第二批落到最后一张
        assertEquals(imageId(IMAGE_COUNT - 1), saved.get(1).imageIdCursor);
        assertEquals(IMAGE_COUNT, saved.get(1).reviewedCount);

        // 扫到结尾：游标清空（下次点按钮从头开新一轮），本轮计数留下
        assertNull(saved.get(2).imageIdCursor);
        assertEquals(IMAGE_COUNT, saved.get(2).reviewedCount);
        assertEquals(10, saved.get(2).deletedCount);
        assertEquals(10, saved.get(2).undecidedCount);
    }

    @Test
    public void testStatusMessageAndDeletedList() throws Exception {
        review();

        AdminImageReviewController.AdminImageReviewTask task = currentTask();
        assertEquals("本轮审完：共审 100 张，删除 10 张，通过 80 张，无结论 10 张", task.statusMsg);
        assertEquals(IMAGE_COUNT, task.currentIndex);
        assertEquals(10, task.deletedCount);
        assertEquals(10, task.deletedImages.size());
        assertFalse(task.isRunning);
    }

    @Test
    public void testDeletedDetailListIsCapped() throws Exception {
        Mockito.reset(wordImageBo);
        when(wordImageBo.reviewImageAndApply(any(), any(), any(), anyBoolean())).thenAnswer(invocation -> {
            Map<String, Object> delete = new HashMap<>();
            delete.put("action", "DELETE");
            delete.put("reason", "全部判删");
            return delete;
        });

        review();

        AdminImageReviewController.AdminImageReviewTask task = currentTask();
        // 总数照实记，明细只留最近 50 条：不然状态响应体会随判删数一路膨胀（实测 1900 条时已 841KB）
        assertEquals(IMAGE_COUNT, task.deletedCount);
        assertEquals(50, task.deletedImages.size());
        assertEquals(imageId(IMAGE_COUNT - 50), task.deletedImages.get(0).get("imageId"));
    }

    @Test
    public void testDirectoryRefreshOnceWhenImagesDeleted() throws Exception {
        review();

        // 本轮判删了 10 张，收尾必须刷一次配图目录：逐张刷 URL 会打爆阿里云每天 2000 条的刷新配额
        verify(wordImageBo, times(1)).refreshWordImageCdnDirectory();
    }

    @Test
    public void testNoDirectoryRefreshWhenNothingDeleted() throws Exception {
        Mockito.reset(wordImageBo);
        when(wordImageBo.reviewImageAndApply(any(), any(), any(), anyBoolean())).thenAnswer(invocation -> {
            Map<String, Object> keep = new HashMap<>();
            keep.put("action", "KEEP");
            return keep;
        });

        review();

        // 一张都没删，就不该白占一次 CDN 目录刷新配额
        verify(wordImageBo, never()).refreshWordImageCdnDirectory();
    }

    /** 个位是 3 的判删、是 7 的 AI 没给结论、其余判过 */
    private static Map<String, Object> verdictOf(String imageId) {
        int index = Integer.parseInt(imageId.substring("img-".length()));
        if (index % 10 == 3) {
            Map<String, Object> verdict = new HashMap<>();
            verdict.put("action", "DELETE");
            verdict.put("reason", "与单词字面义无关");
            return verdict;
        }
        if (index % 10 == 7) {
            return null;
        }
        Map<String, Object> verdict = new HashMap<>();
        verdict.put("action", "KEEP");
        return verdict;
    }

    private static String imageId(int index) {
        return String.format("img-%03d", index);
    }

    private void review() throws Exception {
        // 相当于管理员刚点过「开启后台审核」，runBatchReview 只在 isRunning 为真时才会送审
        currentTask().isRunning = true;
        Method method = AdminImageReviewController.class.getDeclaredMethod("runBatchReview", String.class,
                AdminImageReviewController.ReviewProgress.class);
        method.setAccessible(true);
        method.invoke(controller, "0", null);
    }

    private List<AdminImageReviewController.ReviewProgress> savedProgress() throws Exception {
        ArgumentCaptor<SysParam> captor = ArgumentCaptor.forClass(SysParam.class);
        verify(sysParamBo, times(3)).createEntity(captor.capture());
        return captor.getAllValues().stream()
                .map(param -> JsonUtils.makeObject(param.getParamValue(),
                        AdminImageReviewController.ReviewProgress.class))
                .collect(Collectors.toList());
    }

    private AdminImageReviewController.AdminImageReviewTask currentTask() throws Exception {
        Field field = AdminImageReviewController.class.getDeclaredField("currentTask");
        field.setAccessible(true);
        return (AdminImageReviewController.AdminImageReviewTask) field.get(controller);
    }

    private static void inject(Object target, String fieldName, Object value) throws Exception {
        Field field = target.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(target, value);
    }
}
