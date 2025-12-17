package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Table;

@Entity
@Table(name = "info_vote_log")
public class InfoVoteLog extends Po {

    @Id
    private InfoVoteLogId id;


    public InfoVoteLogId getId() {
        return id;
    }

    public void setId(InfoVoteLogId id) {
        this.id = id;
    }

    @Column(name = "word_additional_info_id")
    private WordAdditionalInfo wordAdditionalInfo;

    @Column(name = "user_id")
    private User user;

    @Column(name = "vote_type", length = 4, nullable = false)
    private String voteType;

    @Column(name = "vote_time", nullable = false)
    private Date voteTime;

    // Constructors

    /**
     * default constructor
     */
    public InfoVoteLog() {
    }

    public WordAdditionalInfo getWordAdditionalInfo() {
        return this.wordAdditionalInfo;
    }

    public void setWordAdditionalInfo(WordAdditionalInfo wordAdditionalInfo) {
        this.wordAdditionalInfo = wordAdditionalInfo;
    }

    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public String getVoteType() {
        return this.voteType;
    }

    public void setVoteType(String voteType) {
        this.voteType = voteType;
    }

    public Date getVoteTime() {
        return voteTime;
    }

    public void setVoteTime(Date voteTime) {
        this.voteTime = voteTime;
    }

}
