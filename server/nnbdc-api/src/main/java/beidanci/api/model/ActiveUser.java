package beidanci.api.model;

public class ActiveUser {
    private final String userName;
    private final String nickName;

    public ActiveUser(String userName, String nickName) {
        this.userName = userName;
        this.nickName = nickName;
    }

    public String getUserName() {
        return userName;
    }

    public String getNickName() {
        return nickName;
    }
}
