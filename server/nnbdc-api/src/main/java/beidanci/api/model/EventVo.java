package beidanci.api.model;

public class EventVo extends UuidVo {


    private TenseType eventType;

    private UserVo user;

    private WordImageVo wordImage;


    public TenseType getEventType() {
        return eventType;
    }

    public void setEventType(TenseType eventType) {
        this.eventType = eventType;
    }

    public UserVo getUser() {
        return user;
    }

    public void setUser(UserVo user) {
        this.user = user;
    }

    public WordImageVo getWordImage() {
        return wordImage;
    }

    public void setWordImage(WordImageVo wordImage) {
        this.wordImage = wordImage;
    }
}
