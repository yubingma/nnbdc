package beidanci.api.model;

import java.util.Date;

public class UserDbLogDto extends Dto {
    private String id;
    private String userId;

    private Integer version;

    private String operate;

    private String tblName;

    private String record;

    /**
     * 记录ID，对于没有定义id的记录，使用自然主键（多个主键用“-”分隔，最多支持4个主键, 所以长度最多131(32*4加3个-号)）
     */
    private String recordId;

    public UserDbLogDto() {
    }

    public UserDbLogDto(String id, String userId, Integer version, String operate, String tblName, String recordId,
            String record, Date createTime, Date updateTime) {
        this.id = id;
        this.userId = userId;
        this.version = version;
        this.operate = operate;
        this.tblName = tblName;
        this.recordId = recordId;
        this.record = record;
        this.createTime = createTime != null ? createTime : new Date();
        this.updateTime = updateTime != null ? updateTime : this.createTime;
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

    public String getRecord() {
        return record;
    }

    public void setRecord(String record) {
        this.record = record;
    }


    public String getRecordId() {
        return recordId;
    }

    public void setRecordId(String recordId) {
        this.recordId = recordId;
    }
}
