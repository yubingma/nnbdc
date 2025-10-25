package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Embeddable;

@Embeddable
public class InfoVoteLogId implements java.io.Serializable {

    // Fields

    /**
     *
     */

    @Column(name = "userId", nullable = false)
    private String userId;

    @Column(name = "infoId", nullable = false)
    private String infoId;

    // Constructors

    /**
     * default constructor
     */
    public InfoVoteLogId() {
    }

    public InfoVoteLogId(String userId, String infoId) {
        this.userId = userId;
        this.infoId = infoId;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public boolean equals(Object other) {
        if ((this == other))
            return true;
        if ((other == null))
            return false;
        if (!(other instanceof InfoVoteLogId))
            return false;
        InfoVoteLogId castOther = (InfoVoteLogId) other;

        return infoId.equals(castOther.infoId) && userId.equals(castOther.userId);
    }

    public int hashCode() {
        int result = 17;

        result = 37 * result + userId.hashCode();
        result = 37 * result + infoId.hashCode();
        return result;
    }

}
