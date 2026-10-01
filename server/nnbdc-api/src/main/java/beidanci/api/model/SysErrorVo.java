package beidanci.api.model;

import java.util.Date;

/**
 * 系统/客户端异常日志（sys_error）的展示对象，供管理后台查看客户端上报的异常。
 *
 * <p>刻意只暴露排查所需的字段：异常分类、关联用户、客户端平台与版本、现场上下文与时间。
 */
public class SysErrorVo extends UuidVo {

    private final String userId;
    private final String nickName;
    private final String errorType;
    private final String details;
    /** 上报客户端的版本号（buildNumber）；服务端自身产生或旧版客户端未上报时为空 */
    private final String clientVersion;
    /** 上报客户端的平台类型：android/ios/macos/windows/linux/browser */
    private final String clientType;
    private final Date createTime;

    public SysErrorVo(String id, String userId, String nickName, String errorType, String details,
            String clientVersion, String clientType, Date createTime) {
        super();
        this.id = id;
        this.userId = userId;
        this.nickName = nickName;
        this.errorType = errorType;
        this.details = details;
        this.clientVersion = clientVersion;
        this.clientType = clientType;
        this.createTime = createTime;
    }

    @Override
    public String getId() {
        return id;
    }

    public String getUserId() {
        return userId;
    }

    public String getNickName() {
        return nickName;
    }

    public String getErrorType() {
        return errorType;
    }

    public String getDetails() {
        return details;
    }

    public String getClientVersion() {
        return clientVersion;
    }

    public String getClientType() {
        return clientType;
    }

    public Date getCreateTime() {
        return createTime;
    }
}
