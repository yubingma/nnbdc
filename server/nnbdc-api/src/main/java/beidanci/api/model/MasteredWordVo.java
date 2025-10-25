package beidanci.api.model;

import java.util.Date;

public class MasteredWordVo extends Vo {

    private UserVo user;
    private WordVo word;
    private Date masterAtTime;


    public MasteredWordVo() {
    }

    public WordVo getWord() {
        return word;
    }

    public void setWord(WordVo word) {
        this.word = word;
    }

    public UserVo getUser() {
        return this.user;
    }

    public void setUser(UserVo user) {
        this.user = user;
    }

    public Date getMasterAtTime() {
        return this.masterAtTime;
    }

    public void setMasterAtTime(Date masterAtTime) {
        this.masterAtTime = masterAtTime;
    }
}
