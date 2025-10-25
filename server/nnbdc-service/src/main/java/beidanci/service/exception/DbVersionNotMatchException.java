package beidanci.service.exception;

public class DbVersionNotMatchException extends Exception {

    private static final long serialVersionUID = 1L;

    public DbVersionNotMatchException(String message) {
        super(message);
    }
}
