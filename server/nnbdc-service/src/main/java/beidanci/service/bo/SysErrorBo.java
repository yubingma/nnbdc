package beidanci.service.bo;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicLong;

import javax.annotation.PostConstruct;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.config.AliyunEmailProperties;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.SysError;
import beidanci.service.po.User;
import beidanci.service.util.EmailUtil;
import beidanci.service.util.Util;

@Service
@Transactional(rollbackFor = Throwable.class)
public class SysErrorBo extends BaseBo<SysError> {

    private static final Logger log = LoggerFactory.getLogger(SysErrorBo.class);

    /**
     * 告警邮件节流间隔：最多 5 分钟发送一封
     */
    private static final long THROTTLE_INTERVAL_MS = 5 * 60 * 1000L;

    /**
     * 上次成功触发告警邮件的时间戳（毫秒）
     */
    private final AtomicLong lastAlertTimestamp = new AtomicLong(0L);

    @Autowired
    private UserBo userBo;

    @Autowired
    private EmailUtil emailUtil;

    @Autowired
    private AliyunEmailProperties emailProperties;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<SysError>() {});
    }

    /**
     * 记录带关联用户的系统/客户端异常，并根据节流规则向管理员发送告警邮件
     */
    public void recordError(String userId, String errorType, String details) throws IllegalAccessException {
        User user = null;
        if (userId != null && !userId.trim().isEmpty()) {
            user = userBo.findById(userId);
        }
        SysError issue = new SysError(user, errorType, details);
        issue.setId(Util.uuid());
        createEntity(issue);

        // 异步旁路判断并触发邮件告警（5分钟节流保护，绝不阻塞主事务与请求）
        triggerEmailAlertAsync(user, errorType, details);
    }

    /**
     * 记录无特定用户的系统级异常（如未登录或游客阶段的异常）
     */
    public void recordError(String errorType, String details) throws IllegalAccessException {
        recordError(null, errorType, details);
    }

    /**
     * 节流检查并尝试获取告警发送许可（包级可见，便于单元测试）
     * 
     * @param now 当前时间戳（毫秒）
     * @return true 表示允许发送；false 表示处于 5 分钟节流窗口内，应跳过
     */
    boolean checkAndThrottle(long now) {
        long last = lastAlertTimestamp.get();
        if (now - last < THROTTLE_INTERVAL_MS) {
            return false;
        }
        return lastAlertTimestamp.compareAndSet(last, now);
    }

    /**
     * 异步评估并发送告警邮件（5分钟节流控制）
     */
    private void triggerEmailAlertAsync(User user, String errorType, String details) {
        long now = System.currentTimeMillis();
        if (!checkAndThrottle(now)) {
            long elapsedSec = (now - lastAlertTimestamp.get()) / 1000;
            log.info("⚠️ 系统错误告警触发 5 分钟节流 (距上次发送 {} 秒)，跳过本次邮件发送: errorType={}", 
                    elapsedSec, errorType);
            return;
        }

        CompletableFuture.runAsync(() -> {
            try {
                sendAlertEmail(user, errorType, details);
            } catch (Exception e) {
                log.error("发送系统错误告警邮件异常: errorType=" + errorType, e);
            }
        });
    }

    /**
     * 组装 HTML 格式告警邮件并发送
     */
    private void sendAlertEmail(User user, String errorType, String details) {
        String adminEmail = emailProperties.getAdminEmail();
        if (adminEmail == null || adminEmail.trim().isEmpty()) {
            adminEmail = "mmyybb3000@icloud.com";
        }

        String subject = "【泡泡单词系统告警】" + errorType;
        String timeStr = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date());
        String userInfo = user != null 
                ? (user.getNickName() != null ? user.getNickName() : user.getUserName()) + " (ID: " + user.getId() + ")" 
                : "未知 / 游客 / 未登录用户";

        String safeDetails = details != null 
                ? details.replace("<", "&lt;").replace(">", "&gt;").replace("\r\n", "<br/>").replace("\n", "<br/>") 
                : "无详细堆栈";

        String html = "<div style=\"font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 650px; padding: 20px; border: 1px solid #e2e8f0; border-radius: 10px; background-color: #ffffff;\">"
                + "<div style=\"display: flex; align-items: center; margin-bottom: 16px;\">"
                + "<h3 style=\"color: #e53e3e; margin: 0;\">🚨 泡泡单词系统告警通知</h3>"
                + "</div>"
                + "<div style=\"background-color: #f7fafc; border-radius: 8px; padding: 12px 16px; margin-bottom: 16px; font-size: 14px; line-height: 1.8;\">"
                + "<div><strong>异常分类：</strong><span style=\"color: #c53030; font-weight: 600;\">" + errorType + "</span></div>"
                + "<div><strong>发生时间：</strong>" + timeStr + "</div>"
                + "<div><strong>关联用户：</strong>" + userInfo + "</div>"
                + "</div>"
                + "<div style=\"font-size: 13px; font-weight: 600; color: #4a5568; margin-bottom: 6px;\">异常堆栈 / 现场上下文：</div>"
                + "<div style=\"background-color: #1a202c; color: #edf2f7; padding: 14px; border-radius: 8px; font-family: ui-monospace, monospace; font-size: 12px; line-height: 1.5; max-height: 400px; overflow-y: auto; word-break: break-all;\">"
                + safeDetails
                + "</div>"
                + "<div style=\"margin-top: 20px; padding-top: 12px; border-top: 1px solid #edf2f7; font-size: 12px; color: #a0aec0; text-align: center;\">"
                + "此邮件为系统自动化监控告警 · 已启用 5 分钟节流保护"
                + "</div>"
                + "</div>";

        String res = emailUtil.sendEmail(adminEmail, "系统管理员", subject, html);
        if ("OK".equals(res)) {
            log.info("✅ 系统错误告警邮件成功送达管理员邮箱: {}, errorType: {}", adminEmail, errorType);
        } else {
            log.warn("⚠️ 系统错误告警邮件发送返回非OK: {}, 收件人: {}", res, adminEmail);
        }
    }
}
