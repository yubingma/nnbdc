package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.Table;

import beidanci.api.model.AdviceRequirementStatus;
import beidanci.api.model.MsgType;
import beidanci.api.model.ClientType;

@Entity
@Table(name = "msg")
public class Msg extends UuidPo {

    @Column(name = "from_user_id")
    private User fromUser;

    @Column(name = "to_user_id")
    private User toUser;

    @Column(name = "content", length = 4000)
    private String content;

    @Enumerated(EnumType.STRING)
    @Column(name = "msg_type", nullable = false, length = 20)
    private MsgType msgType;

    @Enumerated(EnumType.STRING)
    @Column(name = "client_type", length = 20)
    private ClientType clientType;

    public Boolean getViewed() {
        return viewed;
    }

    public void setViewed(Boolean viewed) {
        this.viewed = viewed;
    }

    @Column(name = "viewed", nullable = false)
    private Boolean viewed;

    public Msg() {
        viewed = false;
    }

    public Msg(MsgType msgType) {
        this.msgType = msgType;
        viewed = false;
    }

    // Property accessors


    public User getFromUser() {
        return this.fromUser;
    }

    public void setFromUser(User fromUser) {
        this.fromUser = fromUser;
    }

    public String getContent() {
        return this.content;
    }

    public void setContent(String content) {
        this.content = content;
    }


    public User getToUser() {
        return toUser;
    }

    public void setToUser(User toUser) {
        this.toUser = toUser;
    }

    public MsgType getMsgType() {
        return msgType;
    }

    public void setMsgType(MsgType msgType) {
        this.msgType = msgType;
    }

    public ClientType getClientType() {
        return clientType;
    }

    public void setClientType(ClientType clientType) {
        this.clientType = clientType;
    }

    @Column(name = "tag", length = 32)
    private String tag;

    public String getTag() {
        return tag;
    }

    public void setTag(String tag) {
        this.tag = tag;
    }

    /**
     * 被引用的消息ID：这条消息是对哪一条的针对性回复。为空表示不是针对性回复。
     * 只允许一层引用，引用不能再被引用。
     */
    @Column(name = "reply_to_id", length = 32)
    private String replyToId;

    public String getReplyToId() {
        return replyToId;
    }

    public void setReplyToId(String replyToId) {
        this.replyToId = replyToId;
    }

    /**
     * 消息级需求的处理状态。仅当 tag 为「需求」时有值，取消需求标记时应置回 null。
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "req_status", length = 20)
    private AdviceRequirementStatus reqStatus;

    public AdviceRequirementStatus getReqStatus() {
        return reqStatus;
    }

    public void setReqStatus(AdviceRequirementStatus reqStatus) {
        this.reqStatus = reqStatus;
    }
}
