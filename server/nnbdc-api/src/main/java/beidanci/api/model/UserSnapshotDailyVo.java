package beidanci.api.model;

import java.util.Date;

public class UserSnapshotDailyVo extends Vo{

    private UserVo user;

    private Integer learnedWords;

    private Integer masteredWords;

    private Integer cowDung;

    private Integer russiaScore;

    private Integer dakaDays;

    public Date getTheDate() {
        return theDate;
    }

    public void setTheDate(Date theDate) {
        this.theDate = theDate;
    }

    private Date theDate;

    public UserVo getUser() {
        return user;
    }

    public void setUser(UserVo user) {
        this.user = user;
    }

    public Integer getLearnedWords() {
        return learnedWords;
    }

    public void setLearnedWords(Integer learnedWords) {
        this.learnedWords = learnedWords;
    }

    public Integer getMasteredWords() {
        return masteredWords;
    }

    public void setMasteredWords(Integer masteredWords) {
        this.masteredWords = masteredWords;
    }

    public Integer getCowDung() {
        return cowDung;
    }

    public void setCowDung(Integer cowDung) {
        this.cowDung = cowDung;
    }

    public Integer getRussiaScore() {
        return russiaScore;
    }

    public void setRussiaScore(Integer russiaScore) {
        this.russiaScore = russiaScore;
    }

    public Integer getDakaDays() {
        return dakaDays;
    }

    public void setDakaDays(Integer dakaDays) {
        this.dakaDays = dakaDays;
    }

    /**
     * default constructor
     */
    public UserSnapshotDailyVo() {
    }

}
