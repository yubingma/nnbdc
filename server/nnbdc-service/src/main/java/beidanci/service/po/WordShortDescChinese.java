package beidanci.service.po;

// JDBC 不再支持 Hibernate 缓存注解
// import org.hibernate.annotations.Cache;
// import org.hibernate.annotations.CacheConcurrencyStrategy;

import javax.persistence.*;

/**
 * 用户为单词的英文短描述提供的中文翻译
 *
 * @author Administrator
 */
@Entity
@Table(name = "word_shortdesc_chinese")
// @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)  // JDBC 不支持缓存
public class WordShortDescChinese extends UuidPo {

    @Column(name = "word_id")
    private Word word;

    @Column(name = "hand")
    private Integer hand;

    @Column(name = "foot")
    private Integer foot;

    @Column(name = "content")
    private String content;

    @Column(name = "author_id")
    private User author;

    public Word getWord() {
        return word;
    }

    public void setWord(Word word) {
        this.word = word;
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

    public User getAuthor() {
        return author;
    }

    public void setAuthor(User author) {
        this.author = author;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }
}
