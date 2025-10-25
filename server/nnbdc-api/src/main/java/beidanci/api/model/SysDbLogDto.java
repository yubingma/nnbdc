package beidanci.api.model;

import java.util.Date;

/**
 * 系统数据日志DTO
 */
public class SysDbLogDto implements Dto {
    private String id;
    private Integer version;
    private String operate;
    private String table_;
    private String recordId;
    private String record;
    private Date createTime;
    private Date updateTime;

    public SysDbLogDto() {
    }

    public SysDbLogDto(String id, Integer version, String operate, String table_,
                       String recordId, String record, Date createTime, Date updateTime) {
        this.id = id;
        this.version = version;
        this.operate = operate;
        this.table_ = table_;
        this.recordId = recordId;
        this.record = record;
        this.createTime = createTime;
        this.updateTime = updateTime;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
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

    public String getTable_() {
        return table_;
    }

    public void setTable_(String table_) {
        this.table_ = table_;
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

