package beidanci.api.model;

import java.util.Date;

/**
 * 一个DTO就是一个数据库原始记录（不含关联对象）
 *
 * @author MaYubing
 */
public abstract class Dto {
    protected Date createTime;
    protected Date updateTime;

    public Date getCreateTime() {
        return createTime == null ? new Date(0) : createTime;
    }

    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }

    public Date getUpdateTime() {
        return updateTime == null ? (createTime == null ? new Date(0) : createTime) : updateTime;
    }

    public void setUpdateTime(Date updateTime) {
        this.updateTime = updateTime;
    }
}
