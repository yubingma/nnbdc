package beidanci.api.model;

public class UserGameVo extends Vo {
    private UserVo user;

    private Integer winCount;

    private Integer loseCount;

    private Integer score;

    private String game;

    public UserVo getUser() {
        return user;
    }

    public void setUser(UserVo user) {
        this.user = user;
    }

    public Integer getWinCount() {
        return winCount;
    }

    public void setWinCount(Integer winCount) {
        this.winCount = winCount;
    }

    public Integer getLoseCount() {
        return loseCount;
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
        return game;
    }

    public void setGame(String game) {
        this.game = game;
    }

    public UserGameVo() {
    }

    public UserGameVo(UserVo user, Integer winCount, Integer loseCount, Integer score, String game) {
        this.user = user;
        this.winCount = winCount;
        this.loseCount = loseCount;
        this.score = score;
        this.game = game;
    }
}
