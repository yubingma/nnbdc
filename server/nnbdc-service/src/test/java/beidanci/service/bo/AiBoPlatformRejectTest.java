package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

/**
 * 配图审核里「平台确定性拒收」的识别测试。
 *
 * 平台明确拒收（内容安全拦截、图片本身不合法）的图，重试多少次都是同一个结果，必须直接判删；
 * 一旦识别漏了、把它当成"偶发失败"，那张图就会永久卡在审核中（实测 2026-10-12 有 241 张这样
 * 卡着，既通不过也删不掉）。反过来，限流和超时是真·偶发失败，绝不能误判成拒收，否则会删掉好图。
 */
public class AiBoPlatformRejectTest {

    @Test
    public void testContentInspectionRejected() {
        String message = "{\"statusCode\":400,\"message\":\"<400> InternalError.Algo.DataInspectionFailed: "
                + "Input image data may contain inappropriate content.\",\"code\":\"DataInspectionFailed\"}";

        String reason = AiBo.platformRejectReason(message);

        assertNotNull(reason);
        assertTrue(reason.contains("内容安全"));
    }

    @Test
    public void testInvalidImageRejected() {
        String message = "{\"statusCode\":400,\"message\":\"<400> InternalError.Algo.InvalidParameter: "
                + "The image length and width do not meet the model restrictions. "
                + "[height:1 or width:1 must be larger than 10]\",\"code\":\"InvalidParameter\"}";

        String reason = AiBo.platformRejectReason(message);

        assertNotNull(reason);
        assertTrue(reason.contains("不合法"));
    }

    @Test
    public void testTransientFailuresAreNotRejected() {
        assertNull(AiBo.platformRejectReason("{\"code\":\"Throttling\",\"message\":\"Requests rate limit exceeded\"}"));
        assertNull(AiBo.platformRejectReason("{\"code\":\"InternalError.Timeout\",\"message\":\"request timeout\"}"));
        assertNull(AiBo.platformRejectReason("Read timed out"));
        assertNull(AiBo.platformRejectReason(null));
    }
}
