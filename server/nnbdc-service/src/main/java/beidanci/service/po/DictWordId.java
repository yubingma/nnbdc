package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Embeddable;

@Embeddable
public class DictWordId implements java.io.Serializable {

    private static final long serialVersionUID = 1L;

    @Column(name = "dictId", nullable = false)
    private String dictId;

    @Column(name = "wordId", nullable = false)
    private String wordId;

    public String getDictId() {
        return dictId;
    }

    public String getWordId() {
        return wordId;
    }

    // Constructors

    /**
     * default constructor
     */
    public DictWordId() {
    }

    public DictWordId(String dictId, String wordId) {
        this.dictId = dictId;
        this.wordId = wordId;
    }

    @Override
    public boolean equals(Object other) {
        if ((this == other))
            return true;
        if ((other == null))
            return false;
        if (!(other instanceof DictWordId))
            return false;
        DictWordId castOther = (DictWordId) other;

        return dictId.equals(castOther.dictId) && wordId.equals(castOther.wordId);
    }

    @Override
    public int hashCode() {
        int result = 17;

        result = 37 * result + dictId.hashCode();
        result = 37 * result + wordId.hashCode();
        return result;
    }

}
