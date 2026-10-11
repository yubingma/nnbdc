package beidanci.service.scheduler;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import beidanci.service.bo.WordImageBo;

/**
 * 兜住卡在「审核中」的配图。
 *
 * 上传时的异步审核可能因为服务重启、进程被杀而半途而废，那张图就永远停在 PENDING
 * （实测有卡了两周的图），既不通过也不删除、也没人再去看它。这里每半小时把卡住的捞出来重审。
 */
@Component
public class WordImageReviewTask {
    private static final Logger log = LoggerFactory.getLogger(WordImageReviewTask.class);

    /** 卡住超过这么久才重审，免得打断正在进行的审核 */
    private static final int STUCK_AFTER_MINUTES = 60;

    /** 每轮最多重审这么多张，给 AI 接口留余量 */
    private static final int MAX_PER_ROUND = 20;

    @Autowired
    private WordImageBo wordImageBo;

    @Scheduled(fixedDelay = 30 * 60 * 1000L, initialDelay = 5 * 60 * 1000L)
    public void reviewStuckPendingImages() {
        try {
            int count = wordImageBo.reviewStuckPendingImages(STUCK_AFTER_MINUTES, MAX_PER_ROUND);
            if (count > 0) {
                log.info("自动重审卡在审核中的配图完成: {} 条", count);
            }
        } catch (Exception e) {
            log.error("自动重审卡在审核中的配图失败", e);
        }
    }
}
