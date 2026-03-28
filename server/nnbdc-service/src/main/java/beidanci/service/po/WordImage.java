package beidanci.service.po;

// JDBC 不再支持 Hibernate 缓存注解
// import org.hibernate.annotations.Cache;
// import org.hibernate.annotations.CacheConcurrencyStrategy;

import javax.persistence.*;

@Entity
@Table(name = "word_image")
// @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)  // JDBC 不支持缓存
public class WordImage extends UuidPo {

    public WordImage(Word word, String imageFile, Integer hand, Integer foot, User author) {
        super();
        this.word = word;
        this.imageFile = imageFile;
        this.hand = hand;
        this.foot = foot;
        this.author = author;
    }

    public WordImage() {
        super();
    }

    @Column(name = "word_id")
    private Word word;

    @Column(name = "image_file")
    private String imageFile;

    @Column(name = "hand")
    private Integer hand;

    @Column(name = "foot")
    private Integer foot;

    @Column(name = "author_id")
    private User author;

    @Column(name = "status")
    private String status;

    @Column(name = "audit_reason")
    private String auditReason;

    public User getAuthor() {
        return author;
    }

    public void setAuthor(User author) {
        this.author = author;
    }

    public Word getWord() {
        return word;
    }

    public void setWord(Word word) {
        this.word = word;
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

    public WordImage(String id, Word word, String imageFile, Integer hand, Integer foot, User author) {
        super();
        this.id= id;
        this.word = word;
        this.imageFile = imageFile;
        this.hand = hand;
        this.foot = foot;
        this.author = author;
    }
}
