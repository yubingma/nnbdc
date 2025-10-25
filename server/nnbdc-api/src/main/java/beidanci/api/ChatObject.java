package beidanci.api;

public class ChatObject {

    private String userId;
    private String nickName;
    private String message;

    public ChatObject() {
    }

    public ChatObject(String userId, String nickName, String message) {
        super();
        this.userId = userId;
        this.message = message;
        this.nickName = nickName;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    public String getNickName() {
        return nickName;
    }

    public void setNickName(String nickName) {
        this.nickName = nickName;
    }

}
