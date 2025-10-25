package beidanci.service.po;

import java.util.Set;

import javax.persistence.CascadeType;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.FetchType;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.OneToMany;
import javax.persistence.Table;

import org.hibernate.annotations.Cache;
import org.hibernate.annotations.CacheConcurrencyStrategy;

@Entity
@Table(name = "word_additional_info")
@Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
public class WordAdditionalInfo extends UuidPo {

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false)
    private User user;

    @ManyToOne
    @JoinColumn(name = "wordId", nullable = false)
    private Word word;

    @Column(name = "content", length = 1024, nullable = false)
    private String content;

    @Column(name = "handCount", nullable = false)
    private Integer handCount;

    @Column(name = "footCount", nullable = false)
    private Integer footCount;

    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE}, mappedBy = "wordAdditionalInfo", fetch = FetchType.LAZY)
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
