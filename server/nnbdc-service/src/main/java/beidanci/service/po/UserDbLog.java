package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

@Entity
@Table(name = "user_db_log")
public class UserDbLog extends UuidPo {

    @Column(name = "userId", length = 32, nullable = false)
    private String userId;

    @Column(name = "version", nullable = false)
    private Integer version;

    @Column(name = "operate", length = 20, nullable = false)
    private String operate;

    @Column(name = "table_", length = 50, nullable = false)
    private String table;

    /**
     * 记录ID，对于没有定义id的记录，使用自然主键（多个主键用“-”分隔，最多支持4个主键, 所以长度最多131(32*4加3个-号)）
     */
    @Column(name = "recordId", length = 131, nullable = false)
    private String recordId;

    /**
     * 记录内容，json格式
     */
    @Column(name = "record", length = 1000, nullable = false)
    private String record;

    public UserDbLog() {
    }

    public UserDbLog(String id, String userId, Integer version, String operate, String table,
            String recordId, String record, Date createTime, Date updateTime) {
        this.id = id;
        this.userId = userId;
        this.version = version;
        this.operate = operate;
        this.table = table;
        this.recordId = recordId;
        this.record = record;
        this.createTime = createTime;
        this.updateTime = updateTime;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public Integer getVersion() {
        return version;
    }

    public void setVersion(Integer version) {
        this.version = version;
    }

    public String getOperate() {
        return operate;
    }

    public void setOperate(String operate) {
        this.operate = operate;
    }

    public String getTable() {
        return table;
    }

    public void setTable(String table) {
        this.table = table;
    }

    public String getRecord() {
        return record;
    }

    public void setRecord(String record) {
        this.record = record;
    }

    @Override
    public String getId() {
        return id;
    }

    public String getRecordId() {
        return recordId;
    }

    public void setRecordId(String recordId) {
        this.recordId = recordId;
    }
}
