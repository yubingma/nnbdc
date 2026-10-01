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

    /** 上报客户端的版本号（buildNumber，如 26092401）；服务端自身产生或旧版客户端未上报时为空 */
    @Column(name = "client_version", length = 32)
    private String clientVersion;

    /** 上报客户端的平台类型（android / ios / macos / windows / linux / browser）；
     *  服务端自身产生或旧版客户端未上报时为空。与版本号一起用于判断问题是否集中在某一端某一版 */
    @Column(name = "client_type", length = 20)
    private String clientType;

    public SysError() {
    }

    public SysError(User user, String errorType, String details) {
        this(user, errorType, details, null, null);
    }

    public SysError(User user, String errorType, String details, String clientVersion, String clientType) {
        this.user = user;
        this.errorType = errorType;
        this.details = details;
        this.clientVersion = clientVersion;
        this.clientType = clientType;
    }

    public String getClientVersion() {
        return clientVersion;
    }

    public void setClientVersion(String clientVersion) {
        this.clientVersion = clientVersion;
    }

    public String getClientType() {
        return clientType;
    }

    public void setClientType(String clientType) {
        this.clientType = clientType;
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
