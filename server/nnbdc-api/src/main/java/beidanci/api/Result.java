package beidanci.api;

import java.io.Serializable;

public class Result<T> implements Serializable {

    private static final long serialVersionUID = 1L;


    private String code;

    private String msg;

    private  T data;

    public static <T> Result<T> success(T data) {
        return success(null, data);
    }

    public static <T> Result<T> success(String msg, T data) {
        return new Result<>("0000", msg, data);
    }

    public static <T> Result<T> fail(String msg) {
        return new Result<>("0001", msg, null);
    }

    public Result() {
    }

    public Result(String code, String msg, T data) {
        assert (code != null);
        this.code = code;
        this.msg = msg;
        this.data = data;
    }

    public Result(boolean success, String msg, T data) {
        this.code = success ? "0000" : "0001";
        this.msg = msg;
        this.data = data;
    }

    public String getCode() {
        return code;
    }

    public void setCode(String code) {
        this.code = code;
    }

    public String getMsg() {
        return msg;
    }

    public void setMsg(String msg) {
        this.msg = msg;
    }

    public T getData() {
        return data;
    }

    public void setData(T data) {
        this.data = data;
    }

    public boolean isSuccess() {
        return code.endsWith("0000");
    }
}
