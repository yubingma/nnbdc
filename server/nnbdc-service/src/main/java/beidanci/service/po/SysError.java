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

    /**
     * 上报当时的用户昵称快照（未登录/游客与服务端自身产生的记录为空）。
     *
     * <p>为什么留快照而不是每次 JOIN user 表实时取：用户改了昵称之后，
     * 历史记录显示的名字会跟着变，跟当时反馈的现场对不上。
     * 展示口径是 {@code COALESCE(本列, user 表的实时昵称)}，
     * 所以改造前的老记录（本列为空）照旧显示实时昵称，不会倒退。
     */
    @Column(name = "nick_name", length = 100)
    private String nickName;

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
        // 昵称快照在构造这一刻从 user 取，调用方无须关心；user 为空（游客/服务端自身）时留空
        this.nickName = user == null ? null : user.getNickName();
        this.errorType = errorType;
        this.details = details;
        this.clientVersion = clientVersion;
        this.clientType = clientType;
    }

    public String getNickName() {
        return nickName;
    }

    public void setNickName(String nickName) {
        this.nickName = nickName;
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
