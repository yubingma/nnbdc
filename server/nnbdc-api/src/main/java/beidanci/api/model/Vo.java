package beidanci.api.model;
import java.util.Date;

/**
 * 值对象的基类。值对象用于对象的传输（值对象也称为DTO）
 *
 * @author MaYubing
 */
public abstract class Vo {
    private Date createTime;
    private Date updateTime;

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
