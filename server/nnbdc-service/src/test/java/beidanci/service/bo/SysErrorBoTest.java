package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import org.junit.jupiter.api.Test;

public class SysErrorBoTest {

    @Test
    public void testThrottleWindow() {
        SysErrorBo sysErrorBo = new SysErrorBo();

        long baseTime = 1700000000000L; // 模拟某一基准时间戳

        // 1. 首次调用，应允许发送告警
        assertTrue(sysErrorBo.checkAndThrottle(baseTime), "首次触发告警必须允许发送");

        // 2. 1 分钟后调用，处于 5 分钟节流窗口内，应被拦截
        assertFalse(sysErrorBo.checkAndThrottle(baseTime + 60 * 1000L), "1分钟内重复告警必须被节流");

        // 3. 4 分 59 秒 999 毫秒调用，仍处于节流窗口内，应被拦截
        assertFalse(sysErrorBo.checkAndThrottle(baseTime + 5 * 60 * 1000L - 1), "4分59秒重复告警必须被节流");

        // 4. 恰好 5 分钟调用，节流窗口结束，应允许发送并更新最后发送时间
        assertTrue(sysErrorBo.checkAndThrottle(baseTime + 5 * 60 * 1000L), "满5分钟后应允许再次发送告警");

        // 5. 新窗口开启后 10 秒调用，应被新窗口节流拦截
        assertFalse(sysErrorBo.checkAndThrottle(baseTime + 5 * 60 * 1000L + 10 * 1000L), "新窗口内告警必须被节流");

        // 6. 再次满 5 分钟（即距上次发送 5 分钟），应再次允许发送
        assertTrue(sysErrorBo.checkAndThrottle(baseTime + 10 * 60 * 1000L), "第二次满5分钟后应允许发送告警");
    }

    @Test
    public void testConcurrentThrottle() throws InterruptedException {
        SysErrorBo sysErrorBo = new SysErrorBo();
        long triggerTime = 1700000000000L;

        int threadCount = 20;
        ExecutorService executor = Executors.newFixedThreadPool(threadCount);
        CountDownLatch startLatch = new CountDownLatch(1);
        CountDownLatch doneLatch = new CountDownLatch(threadCount);
        AtomicInteger successCount = new AtomicInteger(0);

        for (int i = 0; i < threadCount; i++) {
            executor.submit(() -> {
                try {
                    startLatch.await();
                    if (sysErrorBo.checkAndThrottle(triggerTime)) {
                        successCount.incrementAndGet();
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                } finally {
                    doneLatch.countDown();
                }
            });
        }

        // 同时放行所有线程进行并发请求
        startLatch.countDown();
        doneLatch.await();
        executor.shutdown();

        // 必须严格保障原子性：同一瞬间的大量并发错误，只能有且仅有 1 个获得发送许可
        assertEquals(1, successCount.get(), "并发爆发式错误场景下，5分钟窗口内必须严格只允许发送1封告警邮件");
    }

    @Test
    public void testThrottleIsIndependentPerErrorType() {
        SysErrorBo sysErrorBo = new SysErrorBo();
        long baseTime = 1700000000000L;

        // 同一时刻不同分类各自只放行一封：某一类刷屏不应把其他类别的告警整体压掉
        assertTrue(sysErrorBo.checkAndThrottle(baseTime, "CLIENT_DATA_INCONSISTENT"), "A 分类首次应允许发送");
        assertFalse(sysErrorBo.checkAndThrottle(baseTime, "CLIENT_DATA_INCONSISTENT"), "A 分类窗口内必须被节流");
        assertTrue(sysErrorBo.checkAndThrottle(baseTime, "SYNC_DATA_PARSE_ERROR"), "B 分类不应被 A 分类压制");
        assertFalse(sysErrorBo.checkAndThrottle(baseTime, "SYNC_DATA_PARSE_ERROR"), "B 分类窗口内必须被节流");

        // 同一个分类超过 5 分钟后恢复
        assertTrue(sysErrorBo.checkAndThrottle(baseTime + 5 * 60 * 1000L, "CLIENT_DATA_INCONSISTENT"),
                "A 分类满 5 分钟后应恢复发送");
    }

    @Test
    public void testTransientNetworkErrorDoesNotAlert() {
        // 用户设备网络抖动：只落库、不发信，避免把真正要处理的告警淹掉
        assertFalse(SysErrorBo.isAlertWorthy("CLIENT_SYNC_NETWORK_JITTER"), "纯网络抖动不应触发告警邮件");
        assertFalse(SysErrorBo.isAlertWorthy(null), "无分类不应触发告警邮件");
        assertFalse(SysErrorBo.isAlertWorthy("  "), "空白分类不应触发告警邮件");

        // 旧版客户端把所有同步失败都归到 CLIENT_SYNC_ERROR（含解析失败、服务端 5xx）：
        // 一律保持告警，宁可多收几封也不能漏掉真问题
        assertTrue(SysErrorBo.isAlertWorthy("CLIENT_SYNC_ERROR"), "旧版同步失败分类必须保持告警");

        // 需要人工介入的分类照常告警
        assertTrue(SysErrorBo.isAlertWorthy("CLIENT_DATA_INCONSISTENT"), "客户端数据不自洽必须告警");
        assertTrue(SysErrorBo.isAlertWorthy("SYNC_DATA_PARSE_ERROR"), "同步数据解析失败必须告警");
        assertTrue(SysErrorBo.isAlertWorthy("DICT_WORD_ORDER_INVALID"), "词序非法必须告警");
    }

    @Test
    public void testReleaseThrottleSlotAllowsRetryAfterEmailFailure() throws Exception {
        SysErrorBo sysErrorBo = new SysErrorBo();
        long occupiedAt = 1700000000000L;
        String errorType = "CLIENT_DATA_INCONSISTENT";

        assertTrue(sysErrorBo.checkAndThrottle(occupiedAt, errorType), "首次应允许发送");

        // 模拟"邮件发送失败"：释放本次占用的节流额度
        Method release = SysErrorBo.class.getDeclaredMethod("releaseThrottleSlot", long.class, String.class);
        release.setAccessible(true);
        release.invoke(sysErrorBo, occupiedAt, errorType);

        // 释放后同一个窗口内应重新允许发送，避免"邮件没发出去却白占 5 分钟额度"
        assertTrue(sysErrorBo.checkAndThrottle(occupiedAt, errorType), "释放额度后应允许重试发送");
    }

    @Test
    public void testThrottleSlotIsRecordedImmediately() throws Exception {
        SysErrorBo sysErrorBo = new SysErrorBo();
        long now = 1700000000000L;
        String errorType = "CLIENT_DATA_INCONSISTENT";

        assertTrue(sysErrorBo.checkAndThrottle(now, errorType));

        // 并发控制依赖"取得许可即写入时间戳"，不能等邮件发完才记录
        Field byType = SysErrorBo.class.getDeclaredField("lastAlertTimestampByType");
        byType.setAccessible(true);
        @SuppressWarnings("unchecked")
        ConcurrentHashMap<String, AtomicLong> map = (ConcurrentHashMap<String, AtomicLong>) byType.get(sysErrorBo);
        assertEquals(now, map.get(errorType).get(), "取得许可时就应立即写入时间戳，避免并发重复发信");
    }
}
