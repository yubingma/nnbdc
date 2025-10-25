package beidanci.service.error;

public interface ErrorCode {
    /**
     * 操作成功
     */
    String CODE_SUCCESS = "NNBDC-0000";

    /**
     * 输入参数无效
     */
    String CODE_INVALID_PARAM = "NNBDC-0001";

    /**
     * 登录失败
     */
    String CODE_LOGIN_FAILED = "NNBDC-0002";


    /**
     * 未知用户
     */
    String CODE_LOGIN_UNKNOWN_USER = "NNBDC-0003";

    /**
     * 错误密码
     */
    String CODE_LOGIN_ERROR_PASSWORD = "NNBDC-0004";

    /**
     * 因操作权限不足，访问被拒绝
     */
    String CODE_FORBIDDEN = "NNBDC-0005";

    /**
     * 用户已存在
     */
    String CODE_USER_IS_ALREADY_EXISTED = "NNBDC-0006";

    /**
     * 用户不存在
     */
    String CODE_USER_IS_NOT_EXISTED = "NNBDC-0007";

    /**
     * 系统异常
     */
    String CODE_EXCEPTION_OCCURED = "NNBDC-0008";

    /**
     * 查询成功，但无数据
     */
    String CODE_SUCCESS_NULL = "NNBDC-0009";

    /**
     * 查询失败
     */
    String CODE_ERROR = "NNBDC-00010";

    /**
     * 外键约束
     */
    String CODE_FK_CONSTRAINT = "NNBDC-0011";

    /**
     * 词书中单词耗尽
     */
    String CODE_WORD_EXHAUSTED = "NNBDC-0012";

    /**
     * 例句数据错误
     */
    String CODE_BAD_SENTENCE = "NNBDC-0013";
}
