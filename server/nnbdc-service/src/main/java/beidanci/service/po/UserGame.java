package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

@Entity
@Table(name = "user_game")
public class UserGame extends Po {

    @Id
    private UserGameId id;

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false, updatable = false, insertable = false)
    private User user;

    @Column(name = "winCount")
    private Integer winCount;

    @Column(name = "loseCount")
    private Integer loseCount;

    @Column(name = "score")
    private Integer score;

    // Constructors

    /**
     * default constructor
     */
    public UserGame() {
    }

    public UserGame(UserGameId id, User user, Integer winCount, Integer loseCount, Integer score) {
        this.id = id;
        this.user = user;
        this.winCount = winCount;
        this.loseCount = loseCount;
        this.score = score;
    }


    public UserGameId getId() {
        return this.id;
    }

    public void setId(UserGameId id) {
        this.id = id;
    }

    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Integer getWinCount() {
        return this.winCount;
    }

    public void setWinCount(Integer winCount) {
        this.winCount = winCount;
    }

    public Integer getLoseCount() {
        return this.loseCount;
    }

    public void setLoseCount(Integer loseCount) {
        this.loseCount = loseCount;
    }

    public Integer getScore() {
        return score;
    }

    public void setScore(Integer score) {
        this.score = score;
    }

    public String getGame() {
        return id.getGame();
    }

}
