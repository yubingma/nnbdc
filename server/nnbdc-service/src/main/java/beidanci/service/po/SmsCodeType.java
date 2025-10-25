package beidanci.service.po;

/**
 * 短信验证码类型枚举
 */
public enum SmsCodeType {
    /**
     * 注册验证码
     */
    REGISTER("注册验证码"),

    /**
     * 登录验证码
     */
    LOGIN("登录验证码"),

    /**
     * 重置密码验证码
     */
    RESET_PASSWORD("重置密码验证码");

    private final String description;

    SmsCodeType(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }
}
