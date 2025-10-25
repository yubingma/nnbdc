package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Embeddable;

@Embeddable
public class LearningDictId implements java.io.Serializable {

    private static final long serialVersionUID = 1L;

    // Fields

    /**
     *
     */

    @Column(name = "userId", nullable = false)
    private String userId;

    @Column(name = "dictId", nullable = false)
    private String dictId;

    public LearningDictId() {
    }

    public LearningDictId(String userId, String dictId) {
        this.userId = userId;
        this.dictId = dictId;
    }

    @Override
    public boolean equals(Object other) {
        if ((this == other))
            return true;
        if ((other == null))
            return false;
        if (!(other instanceof LearningDictId))
            return false;
        LearningDictId castOther = (LearningDictId) other;

        return dictId.equals(castOther.dictId) && userId.equals(castOther.userId);
    }

    @Override
    public int hashCode() {
        int result = 17;

        result = 37 * result + userId.hashCode();
        result = 37 * result + dictId.hashCode();
        return result;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getDictId() {
        return dictId;
    }

    public void setDictId(String dictId) {
        this.dictId = dictId;
    }


}
