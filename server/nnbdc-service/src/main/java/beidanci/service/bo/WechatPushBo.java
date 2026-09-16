package beidanci.service.bo;

import java.sql.Timestamp;
import java.util.Date;

import javax.annotation.PostConstruct;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.WechatAuthEvent;
import beidanci.service.util.WechatPushCrypto;

/**
 * 微信开放平台「消息推送」业务逻辑: 接收「授权用户信息变更」事件（用户撤回授权 / 资料变更 / 完成注销）并落库，
 * 再按事件类型执行对应的合规动作。
 *
 * 处理规则：清空微信来源的昵称与头像、保留 openid/unionid（见 {@link UserBo#clearWechatProfile}）。
 */
@Service
@Transactional(rollbackFor = Throwable.class)
public class WechatPushBo extends BaseBo<WechatAuthEvent> {

    private static final Logger logger = LoggerFactory.getLogger(WechatPushBo.class);

    /** 事件类型：用户撤回授权 */
    private static final String EVENT_REVOKE = "user_authorization_revoke";

    /** 事件类型：用户资料变更（微信侧清理了风险资料） */
    private static final String EVENT_INFO_MODIFIED = "user_info_modified";

    /** 事件类型：用户完成注销 */
    private static final String EVENT_CANCELLATION = "user_authorization_cancellation";

    @Value("${wechat_app_id:wx42e6014d1927e5f0}")
    private String appId;

    /** 开放平台「消息推送」中配置的 Token 令牌，必须与后台填写值一致 */
    @Value("${wechat_push_token:}")
    private String pushToken;

    /** 开放平台「消息推送」中配置的 EncodingAESKey */
    @Value("${wechat_push_encoding_aes_key:}")
    private String encodingAesKey;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @Autowired
    private UserBo userBo;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<WechatAuthEvent>() {
        });
    }

    /**
     * 校验开放平台点击「提交」时发起的 URL 验证请求。
     */
    public boolean verifyUrl(String timestamp, String nonce, String signature) {
        return WechatPushCrypto.verifyUrlSignature(requirePushToken(), timestamp, nonce, signature);
    }

    /**
     * 处理一次事件推送: 验签、解密，然后落库。
     *
     * @throws InvalidSignatureException msg_signature 校验失败，请求并非来自微信（或 Token 配置与后台不一致）
     */
    public void handlePush(String timestamp, String nonce, String msgSignature, String body) {
        String token = requirePushToken();
        if (encodingAesKey.isEmpty()) {
            throw new IllegalStateException("微信推送 EncodingAESKey 未配置(wechat_push_encoding_aes_key)，无法解密推送报文");
        }

        String encrypt = readEncrypt(body);
        if (!WechatPushCrypto.verifyMsgSignature(token, timestamp, nonce, encrypt, msgSignature)) {
            throw new InvalidSignatureException("msg_signature 校验失败");
        }

        recordEvent(WechatPushCrypto.decrypt(encodingAesKey, encrypt, appId));
    }

    /**
     * 处理解密后的事件明文: 查重、落库、执行合规动作。重复投递的事件直接忽略。
     */
    void recordEvent(String payload) {
        WechatAuthEvent event = parseEvent(objectMapper, payload);

        if (isAlreadyRecorded(event)) {
            logger.info("微信授权变更事件重复投递，已忽略: event={}, openId={}, eventTime={}", event.getEvent(),
                    event.getOpenId(), event.getEventTime());
            return;
        }

        try {
            createEntity(event);
        } catch (DuplicateKeyException e) {
            // 并发重复投递(两个请求同时通过了上面的查重)。PostgreSQL 里唯一键冲突会把整个事务标记为 aborted，
            // 之后连 SELECT 都会失败(25P02)，因此这里必须抛出、让事务回滚；微信重试时会命中查重分支。
            throw new IllegalStateException("并发重复投递的微信授权变更事件: openId=" + event.getOpenId(), e);
        }

        logger.info("收到微信授权变更事件: event={}, openId={}, unionId={}, revokeInfo={}, eventTime={}",
                event.getEvent(), event.getOpenId(), event.getUnionId(), event.getRevokeInfo(), event.getEventTime());

        applyEvent(event);
    }

    /**
     * 事件是否已经记录过（按微信侧的事件自然键判断）。
     *
     * 先查后插，而不是"插入失败再捕获唯一键冲突"：PostgreSQL 中语句一旦失败，整个事务就进入 aborted 状态，
     * 后续任何语句（包括清理用的 SELECT）都会报 25P02，捕获异常无法恢复。
     */
    boolean isAlreadyRecorded(WechatAuthEvent event) {
        String sql = "SELECT count(*) FROM wechat_auth_event WHERE app_id = :appId AND event = :event"
                + " AND open_id IS NOT DISTINCT FROM :openId AND revoke_info IS NOT DISTINCT FROM :revokeInfo"
                + " AND event_time = :eventTime";
        MapSqlParameterSource params = new MapSqlParameterSource("appId", event.getAppId())
                .addValue("event", event.getEvent())
                .addValue("openId", event.getOpenId())
                .addValue("revokeInfo", event.getRevokeInfo())
                .addValue("eventTime", new Timestamp(event.getEventTime().getTime()));

        Integer count = namedParameterJdbcTemplate.queryForObject(sql, params, Integer.class);
        return count != null && count > 0;
    }

    /**
     * 事件落库后执行对应的合规动作。
     *
     * 撤回授权与资料变更都只清空微信来源的昵称/头像、保留 openid/unionid（理由见 UserBo.clearWechatProfile）；
     * 用户完成注销涉及账号本身的删除，规则未定，因此只告警要求人工处理。
     */
    void applyEvent(WechatAuthEvent event) {
        switch (event.getEvent()) {
            case EVENT_REVOKE, EVENT_INFO_MODIFIED -> {
                int cleared = userBo.clearWechatProfile(event.getOpenId(), event.getUnionId());
                logger.info("微信授权变更事件已处理: event={}, openId={}, 清理用户数={}", event.getEvent(),
                        event.getOpenId(), cleared);
            }
            case EVENT_CANCELLATION -> logger.warn("收到用户注销事件，账号数据如何处理需人工确认: openId={}, unionId={}, eventTime={}",
                    event.getOpenId(), event.getUnionId(), event.getEventTime());
            default -> logger.warn("收到未知的微信推送事件类型: event={}, openId={}", event.getEvent(),
                    event.getOpenId());
        }
    }

    /**
     * 解析解密后的事件明文。
     */
    static WechatAuthEvent parseEvent(ObjectMapper objectMapper, String payload) {
        JsonNode json;
        try {
            json = objectMapper.readTree(payload);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("微信推送明文不是合法 JSON: " + payload, e);
        }

        String event = text(json, "Event");
        String eventAppId = text(json, "AppID");
        if (event == null || eventAppId == null) {
            throw new IllegalArgumentException("微信推送明文缺少 Event 或 AppID 字段: " + payload);
        }
        if (!json.hasNonNull("CreateTime")) {
            throw new IllegalArgumentException("微信推送明文缺少 CreateTime 字段: " + payload);
        }

        WechatAuthEvent result = new WechatAuthEvent();
        result.setAppId(eventAppId);
        result.setEvent(event);
        result.setOpenId(text(json, "OpenID"));
        result.setUnionId(text(json, "UnionID"));
        result.setRevokeInfo(text(json, "RevokeInfo"));
        result.setEventTime(new Date(json.get("CreateTime").asLong() * 1000L));
        result.setRawPayload(payload);
        return result;
    }

    /** 取出安全模式报文体中的 Encrypt 密文 */
    private String readEncrypt(String body) {
        JsonNode json;
        try {
            json = objectMapper.readTree(body);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("微信推送报文体不是合法 JSON: " + body, e);
        }

        JsonNode encrypt = json.get("Encrypt");
        if (encrypt == null || encrypt.asText().isEmpty()) {
            throw new IllegalArgumentException(
                    "微信推送报文体缺少 Encrypt 字段，请确认开放平台的消息加解密方式为「安全模式」: " + body);
        }
        return encrypt.asText();
    }

    private String requirePushToken() {
        if (pushToken.isEmpty()) {
            throw new IllegalStateException("微信推送 Token 未配置(wechat_push_token)，无法校验推送请求");
        }
        return pushToken;
    }

    private static String text(JsonNode json, String field) {
        JsonNode value = json.get(field);
        return value == null || value.isNull() ? null : value.asText();
    }

    /** msg_signature 校验失败: 请求并非来自微信（或 Token 配置与后台不一致） */
    public static class InvalidSignatureException extends RuntimeException {
        private static final long serialVersionUID = 1L;

        public InvalidSignatureException(String message) {
            super(message);
        }
    }
}
