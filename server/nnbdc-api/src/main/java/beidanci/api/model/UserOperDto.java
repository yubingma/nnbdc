package beidanci.api.model;

import java.util.Date;

public class UserOperDto implements Dto {
    private String id;
    private String userId;
    private String operType;  // 操作类型：LOGIN、START_LEARN、DAKA
    private Date operTime;    // 操作时间
    private String remark;    // 备注信息
    private Date createTime;
    private Date updateTime;

    public UserOperDto() {
    }

    public UserOperDto(String id, String userId, String operType, Date operTime,
                          String remark, Date createTime, Date updateTime) {
        this.id = id;
        this.userId = userId;
        this.operType = operType;
        this.operTime = operTime;
        this.remark = remark;
        this.createTime = createTime;
        this.updateTime = updateTime;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getOperType() {
        return operType;
    }

    public void setOperType(String operType) {
        this.operType = operType;
    }

    public Date getOperTime() {
        return operTime;
    }

    public void setOperTime(Date operTime) {
        this.operTime = operTime;
    }

    public String getRemark() {
        return remark;
    }

    public void setRemark(String remark) {
        this.remark = remark;
    }

    public Date getCreateTime() {
        return createTime;
    }

    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }

    public Date getUpdateTime() {
        return updateTime;
    }

    public void setUpdateTime(Date updateTime) {
        this.updateTime = updateTime;
    }
}
