package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.Table;

// JDBC 不再支持 Hibernate 缓存注解
// import org.hibernate.annotations.Cache;
// import org.hibernate.annotations.CacheConcurrencyStrategy;

import beidanci.api.model.TenseType;

/**
 * 动词的时态
 *
 * @author Administrator
 */
@Entity
@Table(name = "verb_tense")
// @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)  // JDBC 不支持缓存
public class VerbTense extends UuidPo {

    @Column(name = "wordId")
    private Word word;

    /**
     * 时态的类型 - ORDR_PMTR
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "tenseType", nullable = false, length = 20)
    private TenseType tenseType;

    @Column(name = "tensedSpell")
    private String tensedSpell;

    public Word getWord() {
        return word;
    }

    public void setWord(Word word) {
        this.word = word;
    }

    public TenseType getTenseType() {
        return tenseType;
    }

    public void setTenseType(TenseType tenseType) {
        this.tenseType = tenseType;
    }

    public String getTensedSpell() {
        return tensedSpell;
    }

    public void setTensedSpell(String tensedSpell) {
        this.tensedSpell = tensedSpell;
    }
}
