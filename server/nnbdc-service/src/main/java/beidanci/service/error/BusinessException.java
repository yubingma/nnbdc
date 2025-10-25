package beidanci.service.error;

public class BusinessException extends RuntimeException {

    private static final long serialVersionUID = 1L;


    private final String errorCode;

    private final String errorMsg;

    public BusinessException(String errorCode, String errorMsg) {
        super(errorMsg);
        this.errorCode = errorCode;
        this.errorMsg = errorMsg;
    }

    public String getErrorCode() {
        return errorCode;
    }

    public String getErrorMsg() {
        return errorMsg;
    }
}
