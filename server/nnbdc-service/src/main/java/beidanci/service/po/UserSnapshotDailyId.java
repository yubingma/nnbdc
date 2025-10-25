package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Embeddable;

@Embeddable
public class UserSnapshotDailyId implements java.io.Serializable {

    private static final long serialVersionUID = 1L;

    @Column(name = "userId", nullable = false, length = 32)
    private String userId;

    @Column(name = "theDate", nullable = false)
    private Date theDate;

    // Constructors

    /**
     * default constructor
     */
    public UserSnapshotDailyId() {
    }

    /**
     * full constructor
     */
    public UserSnapshotDailyId(String userId, Date theDate) {
        this.userId = userId;
        this.theDate = theDate;
    }

    public Date getTheDate() {
        return this.theDate;
    }

    public void setTheDate(Date theDate) {
        this.theDate = theDate;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    @Override
    public boolean equals(Object other) {
        if ((this == other))
            return true;
        if ((other == null))
            return false;
        if (!(other instanceof UserSnapshotDailyId))
            return false;
        UserSnapshotDailyId castOther = (UserSnapshotDailyId) other;

        return userId.equals(castOther.userId) && theDate.equals(castOther.theDate);
    }

    @Override
    public int hashCode() {
        int result = 17;

        result = 37 * result + userId.hashCode();
        result = 37 * result + theDate.hashCode();
        return result;
    }

}
