package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

/**
 * 系统与客户端异常日志表
 */
@Entity
@Table(name = "sys_error")
public class SysError extends UuidPo {

    @Column(name = "user_id")
    private User user;

    @Column(name = "error_type", nullable = false, length = 64)
    private String errorType;

    @Column(name = "details", nullable = true, columnDefinition = "TEXT")
    private String details;

    public SysError() {
    }

    public SysError(User user, String errorType, String details) {
        this.user = user;
        this.errorType = errorType;
        this.details = details;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public String getErrorType() {
        return errorType;
    }

    public void setErrorType(String errorType) {
        this.errorType = errorType;
    }

    public String getDetails() {
        return details;
    }

    public void setDetails(String details) {
        this.details = details;
    }
}
