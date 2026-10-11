package beidanci.service.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import org.junit.jupiter.api.Test;

import beidanci.service.util.JsonUtils;

/**
 * 批量审图进度（存在 sys_param 里的 JSON）的读写测试。
 *
 * 这份进度决定"服务重启后从哪里接着审"，一旦字段读写对不上，游标就会静默丢失、
 * 每次重启都从头扫（或者更糟：跳到某处把中间的图整段漏掉）。所以这里把序列化往返钉住。
 */
public class AdminImageReviewProgressTest {

    @Test
    public void testProgressJsonRoundTrip() {
        AdminImageReviewController.ReviewProgress progress = new AdminImageReviewController.ReviewProgress();
        progress.dictId = "0";
        progress.imageIdCursor = "854970";
        progress.reviewedCount = 120;
        progress.deletedCount = 3;
        progress.undecidedCount = 1;
        progress.updatedAt = "2026-10-11 21:30";

        AdminImageReviewController.ReviewProgress back = JsonUtils
                .makeObject(JsonUtils.toJson(progress), AdminImageReviewController.ReviewProgress.class);

        assertEquals("0", back.dictId);
        assertEquals("854970", back.imageIdCursor);
        assertEquals(120, back.reviewedCount);
        assertEquals(3, back.deletedCount);
        assertEquals(1, back.undecidedCount);
        assertEquals("2026-10-11 21:30", back.updatedAt);
    }

    @Test
    public void testFinishedRoundKeepsNullCursor() {
        AdminImageReviewController.ReviewProgress progress = new AdminImageReviewController.ReviewProgress();
        progress.dictId = "0";
        progress.imageIdCursor = null;
        progress.reviewedCount = 34664;
        progress.deletedCount = 12;

        AdminImageReviewController.ReviewProgress back = JsonUtils
                .makeObject(JsonUtils.toJson(progress), AdminImageReviewController.ReviewProgress.class);

        // 游标为空 = 这一轮已审完，下次点按钮从头开新一轮
        assertNull(back.imageIdCursor);
        assertEquals(34664, back.reviewedCount);
    }
}
