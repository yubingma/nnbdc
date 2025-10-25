package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.FetchType;
import javax.persistence.Id;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

@Entity
@Table(name = "user_snapshot_daily")
public class UserSnapshotDaily extends Po {

    @Id
    private UserSnapshotDailyId id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "userId", nullable = false, insertable = false, updatable = false)
    private User user;

    @Column(name = "learnedWords", nullable = false)
    private Integer learnedWords;

    @Column(name = "masteredWords", nullable = false)
    private Integer masteredWords;

    @Column(name = "cowDung", nullable = false)
    private Integer cowDung;

    @Column(name = "russiaScore", nullable = false)
    private Integer russiaScore;

    @Column(name = "dakaDays", nullable = false)
    private Integer dakaDays;

    // Constructors

    /**
     * default constructor
     */
    public UserSnapshotDaily() {
    }

    /**
     * full constructor
     */
    public UserSnapshotDaily(UserSnapshotDailyId id, User user, Integer learnedWords, Integer masteredWords,
                             Integer cowDung, Integer russiaScore, Integer dakaDays) {
        this.id = id;
        this.user = user;
        this.learnedWords = learnedWords;
        this.masteredWords = masteredWords;
        this.cowDung = cowDung;
        this.russiaScore = russiaScore;
        this.dakaDays = dakaDays;
    }


    public UserSnapshotDailyId getId() {
        return this.id;
    }

    public void setId(UserSnapshotDailyId id) {
        this.id = id;
    }

    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Integer getLearnedWords() {
        return this.learnedWords;
    }

    public void setLearnedWords(Integer learnedWords) {
        this.learnedWords = learnedWords;
    }

    public Integer getMasteredWords() {
        return this.masteredWords;
    }

    public void setMasteredWords(Integer masteredWords) {
        this.masteredWords = masteredWords;
    }

    public Integer getCowDung() {
        return this.cowDung;
    }

    public void setCowDung(Integer cowDung) {
        this.cowDung = cowDung;
    }

    public Integer getRussiaScore() {
        return this.russiaScore;
    }

    public void setRussiaScore(Integer russiaScore) {
        this.russiaScore = russiaScore;
    }

    public Integer getDakaDays() {
        return this.dakaDays;
    }

    public void setDakaDays(Integer dakaDays) {
        this.dakaDays = dakaDays;
    }

    public Date getTheDate() {
        return id.getTheDate();
    }

    @Override
    public boolean equals(Object obj) {
        if (this == obj) return true;
        if (obj == null || getClass() != obj.getClass()) return false;
        UserSnapshotDaily that = (UserSnapshotDaily) obj;
        return id.equals(that.id);
    }

    @Override
    public int hashCode() {
        return id.hashCode();
    }

}
