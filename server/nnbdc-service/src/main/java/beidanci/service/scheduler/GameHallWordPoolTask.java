package beidanci.service.scheduler;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import beidanci.service.socket.system.game.russia.Russia;

/**
 * 游戏大厅"当日用词池"的准备工作。
 *
 * 大厅的用词是按天抽样的（一个厅每天最多 2000 个词，见 HallWordSampler），
 * 而准备一份池子要 0.4~1.8 秒（词书分组递归加载 + 释义批量查询）。
 * 这笔开销绝不能落在 socket 事件循环线程上——那会连累同一线程上的其他玩家。
 * 所以这里统一在后台单线程里串行准备：
 * <ul>
 *   <li><b>服务启动后预热一次</b>：玩家进厅时池子已经在内存里，不用等；</li>
 *   <li><b>每天零点轮转</b>：换成新一天的词；</li>
 *   <li><b>每 30 分钟补齐</b>：覆盖运行期新建成的大厅。</li>
 * </ul>
 * 三件事都是同一个幂等操作（准备当日池），所以走同一条路径；
 * 真正的"是不是新的一天"判定在 {@code Hall.getWordPool()} 里，不会因为漏跑定时任务而出错。
 */
@Component
public class GameHallWordPoolTask {
    private static final Logger log = LoggerFactory.getLogger(GameHallWordPoolTask.class);

    @Autowired
    private Russia russia;

    /**
     * 单线程后台执行：串行准备各厅词池，避免并发打数据库
     */
    private final ExecutorService worker = Executors.newSingleThreadExecutor(runnable -> {
        Thread thread = new Thread(runnable, "game-hall-word-pool");
        thread.setDaemon(true);
        return thread;
    });

    /**
     * 上一次准备还没结束时，不重复排队
     */
    private final AtomicBoolean running = new AtomicBoolean(false);

    /**
     * 服务启动完成后预热一次
     */
    @EventListener(ApplicationReadyEvent.class)
    public void prewarmOnStartup() {
        submit("服务启动预热");
    }

    /**
     * 每天零点把各厅词池换成新一天的
     */
    @Scheduled(cron = "0 0 0 * * ?")
    public void rotateAtMidnight() {
        submit("零点轮转");
    }

    /**
     * 每 30 分钟补齐一次（运行期新建成的大厅、或上面两次没轮到的）
     */
    @Scheduled(fixedDelay = 30 * 60 * 1000L, initialDelay = 30 * 60 * 1000L)
    public void fillMissingHalls() {
        submit("定期补齐");
    }

    private void submit(String reason) {
        if (!running.compareAndSet(false, true)) {
            log.info(String.format("上一次词池准备还没结束，跳过本次（%s）", reason));
            return;
        }
        worker.submit(() -> {
            try {
                russia.prepareAllWordPools(reason);
            } catch (Exception e) {
                log.error(String.format("准备游戏大厅用词池失败（%s）", reason), e);
            } finally {
                running.set(false);
            }
        });
    }
}
