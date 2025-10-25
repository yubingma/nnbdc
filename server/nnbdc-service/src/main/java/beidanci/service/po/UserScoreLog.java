package beidanci.service.po;

import java.sql.Timestamp;
import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

@Entity
@Table(name = "user_score_log")
public class UserScoreLog extends UuidPo {

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false, updatable = false, insertable = false)
    private User user;

    @Column(name = "delta")
    private Integer delta;

    @Column(name = "score")
    private Integer score;

    @Column(name = "theTime")
    private Date theTime;

    @Column(name = "reason", length = 1024)
    private String reason;

    // Constructors

    /**
     * default constructor
     */
    public UserScoreLog() {
    }

    /**
     * full constructor
     */
    public UserScoreLog(User user, Integer delta, Integer score, Timestamp theTime, String reason) {
        this.user = user;
        this.delta = delta;
        this.score = score;
        this.theTime = theTime;
        this.reason = reason;
    }


    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Integer getDelta() {
        return this.delta;
    }

    public void setDelta(Integer delta) {
        this.delta = delta;
    }

    public Integer getScore() {
        return this.score;
    }

    public void setScore(Integer score) {
        this.score = score;
    }

    public Date getTheTime() {
        return this.theTime;
    }

    public void setTheTime(Date theTime) {
        this.theTime = theTime;
    }

    public String getReason() {
        return this.reason;
    }

    public void setReason(String reason) {
        this.reason = reason;
    }

}
