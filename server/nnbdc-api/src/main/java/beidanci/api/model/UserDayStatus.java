package beidanci.api.model;

/**
 * 用户每日状态(未登录/未学习/未打卡)
 */
public enum UserDayStatus {
    /**
     * 未登录
     */
    NOT_LOGIN,

    /**
     * 已登录
     */
    LOGGEDIN,

    /**
     * 已学习
     */
    STUDIED,

    /**
     * 已打卡
     */
    DAKAED
}
