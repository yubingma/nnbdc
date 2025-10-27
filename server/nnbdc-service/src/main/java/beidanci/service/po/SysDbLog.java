package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

/**
 * 系统数据变更日志表
 * 用于记录UGC内容（Sentences、WordImages、WordShortDescChinese）的变更
 */
@Entity
@Table(name = "sys_db_log")
public class SysDbLog extends UuidPo {


    @Column(name = "version", nullable = false)
    private Integer version;

    @Column(name = "operate", length = 20, nullable = false)
    private String operate;

    @Column(name = "tblName", length = 50, nullable = false)
    private String table;

    @Column(name = "recordId", length = 131, nullable = false)
    private String recordId;

    @Column(name = "record", columnDefinition = "TEXT", nullable = false)
    private String record;

    public SysDbLog() {
    }

    public SysDbLog(String id, Integer version, String operate, String table,
                    String recordId, String record) {
        this.id = id;
        this.version = version;
        this.operate = operate;
        this.table = table;
        this.recordId = recordId;
        this.record = record;
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

    public String getRecordId() {
        return recordId;
    }

    public void setRecordId(String recordId) {
        this.recordId = recordId;
    }

    public String getRecord() {
        return record;
    }

    public void setRecord(String record) {
        this.record = record;
    }
}

