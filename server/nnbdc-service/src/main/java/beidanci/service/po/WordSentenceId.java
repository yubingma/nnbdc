package beidanci.service.po;

import java.io.Serializable;

import javax.persistence.Column;
import javax.persistence.Embeddable;

@Embeddable
public class WordSentenceId implements Serializable {

    private static final long serialVersionUID = 1L;

    @Column(name = "wordId", nullable = false)
    private String wordId;

    @Column(name = "sentenceId", nullable = false)
    private String sentenceId;

    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    public WordSentenceId() {
    }

    public WordSentenceId(String wordId, String sentenceId) {
        this.wordId = wordId;
        this.sentenceId = sentenceId;
    }

    public String getSentenceId() {
        return sentenceId;
    }

    public void setSentenceId(String sentenceId) {
        this.sentenceId = sentenceId;
    }

    @Override
    public boolean equals(Object other) {
        if ((this == other))
            return true;
        if ((other == null))
            return false;
        if (!(other instanceof WordSentenceId))
            return false;
        WordSentenceId castOther = (WordSentenceId) other;

        return wordId.equals(castOther.wordId) && sentenceId.equals(castOther.sentenceId);
    }

    @Override
    public int hashCode() {
        int result = 17;

        result = 37 * result + wordId.hashCode();
        result = 37 * result + sentenceId.hashCode();
        return result;
    }
}
