package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

import beidanci.api.model.MsgType;
import beidanci.api.model.ClientType;

@Entity
@Table(name = "msg")
public class Msg extends UuidPo {



    @ManyToOne
    @JoinColumn(name = "fromUserId", nullable = false)
    private User fromUser;

    @ManyToOne
    @JoinColumn(name = "toUserId", nullable = false)
    private User toUser;

    @Column(name = "content", length = 4000)
    private String content;

    @Enumerated(EnumType.STRING)
    @Column(name = "msgType", nullable = false, length = 20)
    private MsgType msgType;

    @Enumerated(EnumType.STRING)
    @Column(name = "clientType", length = 20)
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
}
