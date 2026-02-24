package beidanci.service.po;

/**
 * 邮箱验证码类型枚举
 */
public enum EmailCodeType {
    /**
     * 注册验证码
     */
    REGISTER("注册验证码"),

    /**
     * 登录验证码
     */
    LOGIN("登录验证码"),

    /**
     * 获取密码验证码（找回密码）
     */
    GET_PASSWORD("获取密码验证码"),

    /**
     * 绑定邮箱验证码
     */
    BIND_EMAIL("绑定邮箱验证码");

    private final String description;

    EmailCodeType(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }
}

