package beidanci.service.po;

import java.sql.Timestamp;
import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

import beidanci.api.model.UserCowDungLogDto;
import beidanci.service.util.Util;

@Entity
@Table(name = "user_cow_dung_log")
public class UserCowDungLog extends UuidPo {

    @Column(name = "user_id")
    private User user;

    @Column(name = "delta", nullable = false)
    private Integer delta;

    @Column(name = "cow_dung", nullable = false)
    private Integer cowDung;

    @Column(name = "the_time", nullable = false)
    private Date theTime;

    @Column(name = "reason", nullable = false)
    private String reason;

    // Constructors

    /**
     * default constructor
     */
    public UserCowDungLog() {
    }

    /**
     * full constructor
     */
    public UserCowDungLog(User user, Integer delta, Integer cowDung, Timestamp theTime, String reason) {
        this.user = user;
        this.delta = delta;
        this.cowDung = cowDung;
        this.theTime = theTime;
        this.reason = reason;
    }

    // Property accessors

    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Integer getDelta() {
        return this.delta;
    }

    public void setDelta(Integer delta) {
        this.delta = delta;
    }

    public Integer getCowDung() {
        return this.cowDung;
    }

    public void setCowDung(Integer cowDung) {
        this.cowDung = cowDung;
    }

    public String getReason() {
        return this.reason;
    }

    public void setReason(String reason) {
        this.reason = reason;
    }

    public Date getTheTime() {
        return theTime;
    }

    public void setTheTime(Date theTime) {
        this.theTime = theTime;
    }

    public static UserCowDungLog fromDto(UserCowDungLogDto dto) {
        UserCowDungLog log = new UserCowDungLog();

        // 设置属性
        String id = dto.getId();
        if (id == null || id.length() > 32) {
            id = Util.uuid();
        }
        log.setId(id);
        log.setCowDung(dto.getCowDung());
        log.setDelta(dto.getDelta());
        log.setReason(dto.getReason());
        log.setCreateTime(dto.getCreateTime());
        log.setUpdateTime(dto.getUpdateTime() != null ? dto.getUpdateTime() : dto.getCreateTime());

        // 设置theTime字段，优先使用DTO中的theTime，如果为null则使用createTime，如果createTime也为null则使用当前时间
        if (dto.getTheTime() != null) {
            log.setTheTime(dto.getTheTime());
        } else if (dto.getCreateTime() != null) {
            log.setTheTime(dto.getCreateTime());
        } else {
            log.setTheTime(new Date());
        }

        return log;
    }

}
