package beidanci.service.po;

// JDBC 不再支持 Hibernate 缓存注解
// import org.hibernate.annotations.Cache;
// import org.hibernate.annotations.CacheConcurrencyStrategy;

import javax.persistence.*;

import beidanci.api.model.Ownerable;

@Entity
@Table(name = "word_image")
// @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)  // JDBC 不支持缓存
public class WordImage extends UuidPo implements Ownerable {

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

    @Column(name = "owner_id")
    private User owner;

    @Column(name = "status")
    private String status;

    @Column(name = "audit_reason")
    private String auditReason;

    public User getAuthor() {
        return author;
    }

    @Override
    public String getOwnerId() {
        return owner != null ? owner.getId() : beidanci.util.Constants.SYS_USER_SYS_ID;
    }

    public User getOwner() {
        return owner;
    }

    public void setOwner(User owner) {
        this.owner = owner;
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
