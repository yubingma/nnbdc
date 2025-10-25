package beidanci.service.po;

import java.io.Serializable;

import javax.persistence.Column;
import javax.persistence.Embeddable;

@Embeddable
public class CigenWordLinkId implements Serializable {

    private static final long serialVersionUID = 1L;
    @Column(name = "cigenId", nullable = false, length = 32)
    private String cigenId;

    @Column(name = "wordId", nullable = false, length = 32)
    private String wordId;

    // Constructors

    /**
     * default constructor
     */
    public CigenWordLinkId() {
    }

    // Property accessors

    public String getCigenId() {
        return this.cigenId;
    }

    public void setCigenId(String cigenId) {
        this.cigenId = cigenId;
    }

    public String getWordId() {
        return this.wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    @Override
    public boolean equals(Object other) {
        if ((this == other))
            return true;
        if ((other == null))
            return false;
        if (!(other instanceof CigenWordLinkId))
            return false;
        CigenWordLinkId castOther = (CigenWordLinkId) other;

        return cigenId.equals(castOther.cigenId) && wordId.equals(castOther.wordId);
    }

    @Override
    public int hashCode() {
        int result = 17;

        result = 37 * result + cigenId.hashCode();
        result = 37 * result + wordId.hashCode();
        return result;
    }

}
