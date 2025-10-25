package beidanci.service.po;

import java.io.Serializable;

import javax.persistence.Column;
import javax.persistence.Embeddable;

@Embeddable
public class SynonymId implements Serializable {

    private static final long serialVersionUID = 1L;
    @Column(name = "meaningItemId")
    private String meaningItemId;

    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    @Column(name = "wordId")
    private String wordId;

    public String getMeaningItemId() {
        return meaningItemId;
    }

    public void setMeaningItemId(String meaningItemId) {
        this.meaningItemId = meaningItemId;
    }

    @Override
    public boolean equals(Object other) {
        if ((this == other))
            return true;
        if ((other == null))
            return false;
        if (!(other instanceof SynonymId))
            return false;
        SynonymId castOther = (SynonymId) other;

        return wordId.equals(castOther.wordId) && meaningItemId.equals(castOther.meaningItemId);
    }

    @Override
    public int hashCode() {
        int result = 17;

        result = 37 * result + wordId.hashCode();
        result = 37 * result + meaningItemId.hashCode();
        return result;
    }
}
