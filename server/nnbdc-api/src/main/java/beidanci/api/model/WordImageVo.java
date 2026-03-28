package beidanci.api.model;

public class WordImageVo extends UuidVo {
    private WordVo word;
    private String imageFile;

    private Integer hand;

    private Integer foot;

    private UserVo author;
    private String status;
    private String auditReason;


    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getAuditReason() {
        return auditReason;
    }

    public void setAuditReason(String auditReason) {
        this.auditReason = auditReason;
    }

    public String getImageFile() {
        return imageFile;
    }

    public void setImageFile(String imageFile) {
        this.imageFile = imageFile;
    }

    public Integer getHand() {
        return hand;
    }

    public void setHand(Integer hand) {
        this.hand = hand;
    }

    public Integer getFoot() {
        return foot;
    }

    public void setFoot(Integer foot) {
        this.foot = foot;
    }

    public UserVo getAuthor() {
        return author;
    }

    public void setAuthor(UserVo author) {
        this.author = author;
    }

    public WordVo getWord() {
        return word;
    }

    public void setWord(WordVo word) {
        this.word = word;
    }
}
