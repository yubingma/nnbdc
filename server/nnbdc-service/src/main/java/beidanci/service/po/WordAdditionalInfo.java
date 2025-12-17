package beidanci.service.po;

import java.util.Set;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

// JDBC 不再支持 Hibernate 缓存注解
// import org.hibernate.annotations.Cache;
// import org.hibernate.annotations.CacheConcurrencyStrategy;

@Entity
@Table(name = "word_additional_info")
// @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)  // JDBC 不支持缓存
public class WordAdditionalInfo extends UuidPo {

    @Column(name = "user_id")
    private User user;

    @Column(name = "word_id")
    private Word word;

    @Column(name = "content", length = 1024, nullable = false)
    private String content;

    @Column(name = "hand_count", nullable = false)
    private Integer handCount;

    @Column(name = "foot_count", nullable = false)
    private Integer footCount;

    private Set<InfoVoteLog> voteLogs;

    // Constructors

    /**
     * default constructor
     */
    public WordAdditionalInfo() {
    }


    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Word getWord() {
        return word;
    }

    public void setWord(Word word) {
        this.word = word;
    }

    public String getContent() {
        return this.content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public Integer getHandCount() {
        return this.handCount;
    }

    public void setHandCount(Integer handCount) {
        this.handCount = handCount;
    }

    public Integer getFootCount() {
        return this.footCount;
    }

    public void setFootCount(Integer footCount) {
        this.footCount = footCount;
    }

    public Set<InfoVoteLog> getVoteLogs() {
        return voteLogs;
    }

    public void setVoteLogs(Set<InfoVoteLog> voteLogs) {
        this.voteLogs = voteLogs;
    }

}
