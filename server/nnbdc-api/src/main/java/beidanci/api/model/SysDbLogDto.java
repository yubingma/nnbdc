package beidanci.api.model;

import java.util.Date;

/**
 * 系统数据日志DTO
 */
public class SysDbLogDto extends Dto {
    private String id;
    private Integer version;
    private String operate;
    private String tblName;
    private String recordId;
    private String record;

    public SysDbLogDto() {
    }

    public SysDbLogDto(String id, Integer version, String operate, String tblName,
                       String recordId, String record, Date createTime, Date updateTime) {
        this.id = id;
        this.version = version;
        this.operate = operate;
        this.tblName = tblName;
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

    public String getTblName() {
        return tblName;
    }

    public void setTblName(String tblName) {
        this.tblName = tblName;
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

