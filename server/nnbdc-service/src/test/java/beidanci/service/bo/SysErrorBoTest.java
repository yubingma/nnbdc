package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

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
}
