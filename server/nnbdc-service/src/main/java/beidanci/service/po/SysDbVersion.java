package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

/**
 * 系统数据库版本表（单例表）
 * 用于追踪UGC内容的全局版本号
 */
@Entity
@Table(name = "sys_db_version")
public class SysDbVersion extends UuidPo {


    @Column(name = "version", nullable = false)
    private Integer version;

    public SysDbVersion() {
    }

    public SysDbVersion(String id, Integer version) {
        this.id = id;
        this.version = version;
    }

    public Integer getVersion() {
        return version;
    }

    public void setVersion(Integer version) {
        this.version = version;
    }
}

