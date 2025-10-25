package beidanci.service.po;

import java.sql.Timestamp;
import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

import beidanci.api.model.MasteredWordDto;

@Entity
@Table(name = "mastered_word")
public class MasteredWord extends Po {

    /**
     *
     */

    @Id
    private MasteredWordId id;

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false, updatable = false, insertable = false)
    private User user;

    @Column(name = "masterAtTime", nullable = false)
    private Date masterAtTime;

    /**
     * default constructor
     */
    public MasteredWord() {
    }

    /**
     * full constructor
     */
    public MasteredWord(MasteredWordId id, User user, Date masterAtTime) {
        this.id = id;
        this.user = user;
        this.masterAtTime = masterAtTime;
    }

    public MasteredWordId getId() {
        return this.id;
    }

    public void setId(MasteredWordId id) {
        this.id = id;
    }

    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Date getMasterAtTime() {
        return this.masterAtTime;
    }

    public void setMasterAtTime(Date masterAtTime) {
        this.masterAtTime = masterAtTime;
    }

    public void setMasterAtTime(Timestamp masterAtTime) {
        this.masterAtTime = masterAtTime;
    }

    public static MasteredWord fromDto(MasteredWordDto dto) {
        MasteredWord masteredWord = new MasteredWord();

        // 设置复合主键
        MasteredWordId id = new MasteredWordId(dto.getUserId(), dto.getWordId());
        masteredWord.setId(id);

        // 设置其他属性
        masteredWord.setMasterAtTime(dto.getMasterAtTime());
        masteredWord.setCreateTime(dto.getCreateTime());
        masteredWord.setUpdateTime(dto.getUpdateTime());

        return masteredWord;
    }

}
