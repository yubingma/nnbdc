-- 微信开放平台「授权用户信息变更」事件表 (wechat_auth_event)
--
-- 背景: 用户撤回授权/资料变更/完成注销时, 微信通过「消息推送」实时事件(或每日汇总邮件)通知开发者,
-- 要求开发者及时删除对应的微信授权信息(昵称/头像等)。服务端此前没有任何接收渠道, 该合规义务是悬空的。
-- 本表原样落库所有收到的推送事件, 作为合规动作的审计依据(处理规则见 UserBo.clearWechatProfile)。
--
-- 幂等: 同一事件可能被重复投递(推送重试、每日邮件与实时推送并存), 因此按事件自然键去重。
-- 保留期: 本表含 openid/unionid, 属"为履行删除义务与审计所必需"; 需另定保留期, 避免长期堆积标识符。

CREATE TABLE IF NOT EXISTS wechat_auth_event (
    id VARCHAR(32) PRIMARY KEY,
    app_id VARCHAR(64) NOT NULL,
    event VARCHAR(64) NOT NULL,
    open_id VARCHAR(100),
    union_id VARCHAR(100),
    revoke_info VARCHAR(50),
    event_time TIMESTAMP NOT NULL,
    raw_payload TEXT NOT NULL,
    create_time TIMESTAMP NOT NULL,
    update_time TIMESTAMP NOT NULL,
    CONSTRAINT uk_wechat_auth_event UNIQUE (app_id, event, open_id, revoke_info, event_time)
);
