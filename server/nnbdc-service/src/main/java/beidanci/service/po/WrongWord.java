package beidanci.service.po;

import java.io.IOException;
import java.util.Objects;

import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

import beidanci.api.model.WordVo;
import beidanci.api.model.WrongWordDto;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.store.WordCache;

@Entity
@Table(name = "user_wrong_word")
public class WrongWord extends Po {


    @Id
    private WrongWordId id;

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false, updatable = false, insertable = false)
    private User user;

    /**
     * default constructor
     */
    public WrongWord() {
    }

    /**
     * minimal constructor
     */
    public WrongWord(WrongWordId id, User user) {
        this.id = id;
        this.user = user;
    }

    public WrongWordId getId() {
        return this.id;
    }

    public void setId(WrongWordId id) {
        this.id = id;
    }

    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public WordVo getWord(WordCache wordCache) throws IOException, ParseException, InvalidMeaningFormatException, EmptySpellException {
        return wordCache.getWordById(id.getWordId(), new String[]{
                "SynonymVo.meaningItem", "SynonymVo.word",  "similarWords", "DictVo.dictWords"});
    }

    /**
     * 从DTO创建WrongWord实体
     */
    public static WrongWord fromDto(WrongWordDto dto) {
        WrongWordId id = new WrongWordId(dto.getUserId(), dto.getWordId());
        WrongWord wrongWord = new WrongWord();
        wrongWord.setId(id);
        if (dto.getCreateTime() != null) {
            wrongWord.setCreateTime(dto.getCreateTime());
        }
        if (dto.getUpdateTime() != null) {
            wrongWord.setUpdateTime(dto.getUpdateTime());
        }
        return wrongWord;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        WrongWord that = (WrongWord) o;
        return id.equals(that.id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id);
    }
}
