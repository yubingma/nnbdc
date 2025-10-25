package beidanci.api.model;

public class DakaVo extends Vo{

    // no Java serialization
    private DakaIdVo id;

    private UserVo user;

    private String text;

    public DakaIdVo getId() {
        return id;
    }

    public void setId(DakaIdVo id) {
        this.id = id;
    }

    public UserVo getUser() {
        return user;
    }

    public void setUser(UserVo user) {
        this.user = user;
    }

    public String getText() {
        return text;
    }

    public void setText(String text) {
        this.text = text;
    }
}
