package beidanci.service.bo;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
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
     * 告警邮件节流间隔：同一分类最多 5 分钟发送一封
     */
    private static final long THROTTLE_INTERVAL_MS = 5 * 60 * 1000L;

    /**
     * 最近一次允许发送告警的时间戳（毫秒），跨分类共用。
     * 仅用于表达"全部错误共用一个窗口"的节流语义（[checkAndThrottle(long)]），
     * 与 [lastAlertTimestampByType] 是两套独立窗口，互不干扰。
     */
    private final AtomicLong lastAlertTimestamp = new AtomicLong(WINDOW_UNSET);

    /**
     * 各分类最近一次允许发送告警的时间戳（毫秒）。
     * 按分类分别节流，避免"某一类刷屏把其他类别的告警整体压掉"，
     * 也避免"某一类的告警把真正要处理的另一类告警顶掉"。
     */
    private final ConcurrentHashMap<String, AtomicLong> lastAlertTimestampByType = new ConcurrentHashMap<>();

    /**
     * 无需告警的分类：客户端明确标注为"纯网络抖动"的同步失败
     * （连接超时、响应超时、连接被中断、DNS 失败等）。
     *
     * <p>这类异常绝大多数是用户设备网络问题，客户端下一轮同步会自动重试成功，
     * 服务端没有任何需要人工干预的动作；而它们数量大，一旦发信会把真正需要处理的
     * 分类（如客户端数据不自洽、同步数据解析失败）淹没掉。
     * 因此仍然照常记录进 sys_error 表供排查，但不再触发告警邮件。
     *
     * <p>注意：不要把 {@code CLIENT_SYNC_ERROR} 也放进来 —— 旧版客户端把所有同步失败
     * （含解析失败、服务端 5xx 等真问题）都归在它名下，一律压掉会漏掉真问题。
     */
    private static final Set<String> TRANSIENT_NETWORK_ERROR_TYPES = Set.of("CLIENT_SYNC_NETWORK_JITTER");

    /** 判定某个分类的异常是否值得给管理员发告警邮件 */
    static boolean isAlertWorthy(String errorType) {
        if (errorType == null || errorType.trim().isEmpty()) {
            return false;
        }
        return !TRANSIENT_NETWORK_ERROR_TYPES.contains(errorType.trim());
    }

    /** 各分类节流窗口的时间戳：0 表示该窗口尚未被占用 */
    private static final long WINDOW_UNSET = 0L;

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
     * 记录带关联用户的系统/客户端异常，并按分类节流规则向管理员发送告警邮件
     */
    public void recordError(String userId, String errorType, String details) throws IllegalAccessException {
        recordError(userId, errorType, details, null, null);
    }

    /**
     * 记录带关联用户与客户端信息的异常。
     * 版本号与平台类型单独成列，便于按"哪一端、哪一版"聚合判断问题是否集中出现。
     */
    public void recordError(String userId, String errorType, String details, String clientVersion, String clientType)
            throws IllegalAccessException {
        User user = null;
        if (userId != null && !userId.trim().isEmpty()) {
            user = userBo.findById(userId);
        }
        SysError issue = new SysError(user, errorType, details, clientVersion, clientType);
        issue.setId(Util.uuid());
        createEntity(issue);

        // 异步旁路判断并触发邮件告警（绝不阻塞主事务与请求）
        triggerEmailAlertAsync(user, errorType, details, clientVersion, clientType);
    }

    /**
     * 记录无特定用户的系统级异常（如未登录或游客阶段的异常）
     */
    public void recordError(String errorType, String details) throws IllegalAccessException {
        recordError(null, errorType, details);
    }

    /**
     * 节流检查并尝试获取告警发送许可（包级可见，便于单元测试）。
     * 语义是"全部错误共用一个窗口"，供不区分分类的调用方使用。
     *
     * @param now 当前时间戳（毫秒）
     * @return true 表示允许发送；false 表示处于节流窗口内，应跳过
     */
    boolean checkAndThrottle(long now) {
        long last = lastAlertTimestamp.get();
        if (last != WINDOW_UNSET && now - last < THROTTLE_INTERVAL_MS) {
            return false;
        }
        return lastAlertTimestamp.compareAndSet(last, now);
    }

    /**
     * 按分类节流检查并尝试获取告警发送许可（包级可见，便于单元测试）。
     *
     * <p>每个分类各有自己的 5 分钟窗口，互不压制：
     * 某一类刷屏不会让其他类别的告警发不出去，某一类的告警也不会被别的类别顶掉。
     *
     * @param now       当前时间戳（毫秒）
     * @param errorType 异常分类
     * @return true 表示允许发送；false 表示该分类处于节流窗口内，应跳过
     */
    boolean checkAndThrottle(long now, String errorType) {
        AtomicLong typeTimestamp = lastAlertTimestampByType.computeIfAbsent(errorType, key -> new AtomicLong(WINDOW_UNSET));
        long lastOfType = typeTimestamp.get();
        if (lastOfType != WINDOW_UNSET && now - lastOfType < THROTTLE_INTERVAL_MS) {
            return false;
        }
        return typeTimestamp.compareAndSet(lastOfType, now);
    }

    /**
     * 发信失败时回退占用掉的节流时间戳，避免"邮件没发出去却把 5 分钟额度用掉"。
     * 只回退到本次占用的那个值，避免覆盖并发场景下别人刚占用的时间戳。
     */
    private void releaseThrottleSlot(long occupiedAt, String errorType) {
        AtomicLong typeTimestamp = lastAlertTimestampByType.get(errorType);
        if (typeTimestamp != null) {
            typeTimestamp.compareAndSet(occupiedAt, WINDOW_UNSET);
        }
    }

    /**
     * 异步评估并发送告警邮件（按分类节流）
     *
     * <p>无条件发信的只有"值得人工处理"的分类；瞬时网络异常只落库不发信。
     */
    private void triggerEmailAlertAsync(User user, String errorType, String details, String clientVersion,
            String clientType) {
        if (!isAlertWorthy(errorType)) {
            log.info("ℹ️ 异常分类无需告警（瞬时网络异常，已记录待排查）: errorType={}", errorType);
            return;
        }
        long now = System.currentTimeMillis();
        if (!checkAndThrottle(now, errorType)) {
            log.info("⚠️ 系统错误告警触发 5 分钟节流（按分类独立计算），跳过本次邮件发送: errorType={}", errorType);
            return;
        }

        CompletableFuture.runAsync(() -> {
            boolean sent = false;
            try {
                sendAlertEmail(user, errorType, details, clientVersion, clientType);
                sent = true;
            } catch (Exception e) {
                log.error("发送系统错误告警邮件异常: errorType=" + errorType, e);
            } finally {
                if (!sent) {
                    // 邮件没发出去，不能白占掉节流额度，否则真实告警会被压 5 分钟
                    releaseThrottleSlot(now, errorType);
                }
            }
        });
    }

    /**
     * 组装 HTML 格式告警邮件并发送
     */
    private void sendAlertEmail(User user, String errorType, String details, String clientVersion,
            String clientType) {
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
                + "<div><strong>客户端版本：</strong>"
                + (clientVersion == null || clientVersion.trim().isEmpty() ? "未上报" : clientVersion)
                + "</div>"
                + "<div><strong>客户端平台：</strong>"
                + (clientType == null || clientType.trim().isEmpty() ? "未上报" : clientType)
                + "</div>"
                + "</div>"
                + "<div style=\"font-size: 13px; font-weight: 600; color: #4a5568; margin-bottom: 6px;\">异常堆栈 / 现场上下文：</div>"
                + "<div style=\"background-color: #1a202c; color: #edf2f7; padding: 14px; border-radius: 8px; font-family: ui-monospace, monospace; font-size: 12px; line-height: 1.5; max-height: 400px; overflow-y: auto; word-break: break-all;\">"
                + safeDetails
                + "</div>"
                + "<div style=\"margin-top: 20px; padding-top: 12px; border-top: 1px solid #edf2f7; font-size: 12px; color: #a0aec0; text-align: center;\">"
                + "此邮件为系统自动化监控告警 · 同一分类 5 分钟内只发一封 · 瞬时网络异常只记录不发信"
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
