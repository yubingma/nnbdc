package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

import org.hibernate.annotations.Cache;
import org.hibernate.annotations.CacheConcurrencyStrategy;

@Entity
@Table(name = "cigen_word_link")
@Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
public class CigenWordLink extends Po {

    @Id
    private CigenWordLinkId id;

    @ManyToOne
    @JoinColumn(name = "cigenId", nullable = false, updatable = false, insertable = false)
    private Cigen cigen;

    @ManyToOne
    @JoinColumn(name = "wordId", nullable = false, updatable = false, insertable = false)
    private Word word;

    @Column(name = "theExplain", length = 1024, nullable = false)
    private String theExplain;

    public Word getWord() {
        return word;
    }

    public void setWord(Word word) {
        this.word = word;
    }
    // Constructors

    /**
     * default constructor
     */
    public CigenWordLink() {
    }

    /**
     * full constructor
     */
    public CigenWordLink(CigenWordLinkId id, Cigen cigen, String theExplain) {
        this.id = id;
        this.cigen = cigen;
        this.theExplain = theExplain;
    }


    public CigenWordLinkId getId() {
        return this.id;
    }

    public void setId(CigenWordLinkId id) {
        this.id = id;
    }

    public Cigen getCigen() {
        return this.cigen;
    }

    public void setCigen(Cigen cigen) {
        this.cigen = cigen;
    }

    public String getTheExplain() {
        return this.theExplain;
    }

    public void setTheExplain(String theExplain) {
        this.theExplain = theExplain;
    }

}
