package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

/**
 * 微信开放平台「授权用户信息变更」事件（用户撤回授权 / 资料变更 / 完成注销）。
 *
 * 微信要求开发者在用户撤回授权后主动删除对应用户的微信授权信息，本表是履行该义务的输入与审计依据。
 * 建表脚本: db_upgrade/latest-to-upgrade/v60_add_wechat_auth_event.sql
 */
@Entity
@Table(name = "wechat_auth_event")
public class WechatAuthEvent extends UuidPo {

    /** 事件所属的移动应用 AppID */
    @Column(name = "app_id", length = 64, nullable = false)
    private String appId;

    /** 事件类型: user_authorization_revoke(撤回) / user_info_modified(资料变更) / user_authorization_cancellation(注销) */
    @Column(name = "event", length = 64, nullable = false)
    private String event;

    /** 授权用户的 OpenID */
    @Column(name = "open_id", length = 100)
    private String openId;

    /** 授权用户的 UnionID */
    @Column(name = "union_id", length = 100)
    private String unionId;

    /** 用户撤回的授权信息。移动应用固定为 301（撤回所有授权信息） */
    @Column(name = "revoke_info", length = 50)
    private String revokeInfo;

    /** 事件发生时间（微信 CreateTime） */
    @Column(name = "event_time", nullable = false)
    private Date eventTime;

    /** 解密后的完整事件报文，用于审计与排障 */
    @Column(name = "raw_payload", columnDefinition = "TEXT", nullable = false)
    private String rawPayload;

    public String getAppId() {
        return appId;
    }

    public void setAppId(String appId) {
        this.appId = appId;
    }

    public String getEvent() {
        return event;
    }

    public void setEvent(String event) {
        this.event = event;
    }

    public String getOpenId() {
        return openId;
    }

    public void setOpenId(String openId) {
        this.openId = openId;
    }

    public String getUnionId() {
        return unionId;
    }

    public void setUnionId(String unionId) {
        this.unionId = unionId;
    }

    public String getRevokeInfo() {
        return revokeInfo;
    }

    public void setRevokeInfo(String revokeInfo) {
        this.revokeInfo = revokeInfo;
    }

    public Date getEventTime() {
        return eventTime;
    }

    public void setEventTime(Date eventTime) {
        this.eventTime = eventTime;
    }

    public String getRawPayload() {
        return rawPayload;
    }

    public void setRawPayload(String rawPayload) {
        this.rawPayload = rawPayload;
    }
}
