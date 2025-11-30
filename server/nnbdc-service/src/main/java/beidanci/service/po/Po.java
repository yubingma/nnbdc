package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.MappedSuperclass;
import javax.persistence.Temporal;
import javax.persistence.TemporalType;

// JDBC 不再支持 Hibernate 注解，创建时间需要在代码中手动设置
// import org.hibernate.annotations.CreationTimestamp;

/**
 * 数据库持久化对象（一般也称为Entity）
 *
 * @author MaYubing
 */
@MappedSuperclass
public abstract class Po {

    /**
     * 对象创建时间
     */
    @Temporal(TemporalType.TIMESTAMP)
    // @CreationTimestamp  // JDBC 不再支持，需要在代码中手动设置
    @Column(name = "createTime", nullable = false)
    protected Date createTime;

    /**
     * 对象最近更新时间
     */
    @Column(name = "updateTime")
    protected Date updateTime;

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
