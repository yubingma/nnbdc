package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Table;

/**
 * 用户操作历史记录实体类
 */
@Entity
@Table(name = "user_oper")
public class UserOper extends Po {


    @Id
    @Column(name = "id", nullable = false, length = 32)
    private String id;

    @Column(name = "userId", nullable = false, length = 32)
    private String userId;

    @Column(name = "operType", nullable = false, length = 20)
    private String operType;  // 操作类型：LOGIN、START_LEARN、DAKA

    @Column(name = "operTime", nullable = false)
    private Date operTime;    // 操作时间

    @Column(name = "remark", nullable = true, length = 200)
    private String remark;    // 备注信息

    public UserOper() {
    }

    public UserOper(String id, String userId, String operType, Date operTime,
                       String remark) {
        this.id = id;
        this.userId = userId;
        this.operType = operType;
        this.operTime = operTime;
        this.remark = remark;
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

    @Override
    public Date getCreateTime() {
        return createTime;
    }

    @Override
    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }

    @Override
    public Date getUpdateTime() {
        return updateTime;
    }

    @Override
    public void setUpdateTime(Date updateTime) {
        this.updateTime = updateTime;
    }
}
