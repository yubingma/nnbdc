package beidanci.api.model;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

import java.util.Date;

/**
 * 客服会话摘要：管理端「意见建议」首屏的一行。
 *
 * 一个用户一行，承载三样东西：这个人的身份、这个会话的待办量（未读几条、含需求几条）、
 * 以及最后一条消息的预览。点进去才拉这个人和客服的完整聊天。
 *
 * 原来管理端是一次拉全量意见建议再在客户端按人平铺，人一多首屏就慢，同一个人还占很多行。
 */
@ApiModel(description = "客服会话摘要")
public class AdviceSessionVo {

    @ApiModelProperty("提意见的用户ID")
    private String userId;

    @ApiModelProperty("用户账号名")
    private String userName;

    @ApiModelProperty("用户昵称")
    private String nickName;

    @ApiModelProperty("用户头像")
    private String wechatAvatar;

    @ApiModelProperty("是否永久会员（管理员在意见反馈页手动授予的）")
    private Boolean premium;

    @ApiModelProperty("这个用户发给客服的未读消息条数")
    private Integer unviewedCount;

    @ApiModelProperty("这个用户发给客服的消息总条数")
    private Integer totalCount;

    @ApiModelProperty("其中被标记为需求的条数")
    private Integer requirementCount;

    @ApiModelProperty("最后一条消息的内容预览（已截断，最长40字）")
    private String lastContent;

    @ApiModelProperty("最后一条消息的类型")
    private MsgType lastMsgType;

    @ApiModelProperty("最后一条消息的时间")
    private Date lastCreateTime;

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

    public Integer getUnviewedCount() {
        return unviewedCount;
    }

    public void setUnviewedCount(Integer unviewedCount) {
        this.unviewedCount = unviewedCount;
    }

    public Integer getTotalCount() {
        return totalCount;
    }

    public void setTotalCount(Integer totalCount) {
        this.totalCount = totalCount;
    }

    public Integer getRequirementCount() {
        return requirementCount;
    }

    public void setRequirementCount(Integer requirementCount) {
        this.requirementCount = requirementCount;
    }

    public String getLastContent() {
        return lastContent;
    }

    public void setLastContent(String lastContent) {
        this.lastContent = lastContent;
    }

    public MsgType getLastMsgType() {
        return lastMsgType;
    }

    public void setLastMsgType(MsgType lastMsgType) {
        this.lastMsgType = lastMsgType;
    }

    public Date getLastCreateTime() {
        return lastCreateTime;
    }

    public void setLastCreateTime(Date lastCreateTime) {
        this.lastCreateTime = lastCreateTime;
    }
}
