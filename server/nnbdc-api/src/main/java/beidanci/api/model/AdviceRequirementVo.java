package beidanci.api.model;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

import java.util.Date;

/**
 * 消息级需求：管理端需求列表里的一张卡片。
 *
 * 需求挂在被标记的那一条消息上，不挂在会话或用户上——一次会话里用户说了几件事，
 * 是需求就标那几条。这张列表是待办，不是聊天记录：一条需求一行，点进去落到原文那条消息上。
 */
@ApiModel(description = "消息级需求")
public class AdviceRequirementVo {

    @ApiModelProperty("被标记为需求的那条消息ID")
    private String id;

    @ApiModelProperty("需求原文")
    private String content;

    @ApiModelProperty("提需求的时间")
    private Date createTime;

    @ApiModelProperty("提出需求的客户端类型")
    private ClientType clientType;

    @ApiModelProperty("提需求的用户ID")
    private String userId;

    @ApiModelProperty("用户账号名")
    private String userName;

    @ApiModelProperty("用户昵称")
    private String nickName;

    @ApiModelProperty("用户头像")
    private String wechatAvatar;

    @ApiModelProperty("是否永久会员")
    private Boolean premium;

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public Date getCreateTime() {
        return createTime;
    }

    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }

    public ClientType getClientType() {
        return clientType;
    }

    public void setClientType(ClientType clientType) {
        this.clientType = clientType;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getUserName() {
        return userName;
    }

    public void setUserName(String userName) {
        this.userName = userName;
    }

    public String getNickName() {
        return nickName;
    }

    public void setNickName(String nickName) {
        this.nickName = nickName;
    }

    public String getWechatAvatar() {
        return wechatAvatar;
    }

    public void setWechatAvatar(String wechatAvatar) {
        this.wechatAvatar = wechatAvatar;
    }

    public Boolean getPremium() {
        return premium;
    }

    public void setPremium(Boolean premium) {
        this.premium = premium;
    }
}
