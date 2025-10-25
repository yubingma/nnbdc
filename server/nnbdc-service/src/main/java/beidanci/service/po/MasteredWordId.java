package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Embeddable;

@Embeddable
public class MasteredWordId implements java.io.Serializable {

    private static final long serialVersionUID = 1L;

    /**
     *
     */

    @Column(name = "userId", nullable = false)
    private String userId;

    public MasteredWordId(String userId, String wordId) {
        this.userId = userId;
        this.wordId = wordId;
    }

    public String getWordId() {
        return wordId;
    }

    public String getUserId() {
        return userId;
    }

    @Column(name = "wordId", nullable = false)
    private String wordId;


    /**
     * default constructor
     */
    public MasteredWordId() {
    }

    @Override
    public boolean equals(Object other) {
        if ((this == other))
            return true;
        if ((other == null))
            return false;
        if (!(other instanceof MasteredWordId))
            return false;
        MasteredWordId castOther = (MasteredWordId) other;

        return wordId.equals(castOther.wordId) && userId.equals(castOther.userId);
    }

    @Override
    public int hashCode() {
        int result = 17;

        result = 37 * result + userId.hashCode();
        result = 37 * result + wordId.hashCode();
        return result;
    }

}
