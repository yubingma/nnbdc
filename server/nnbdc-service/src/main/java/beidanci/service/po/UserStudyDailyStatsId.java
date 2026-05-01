package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Embeddable;

@Embeddable
public class UserStudyDailyStatsId implements java.io.Serializable {

    private static final long serialVersionUID = 1L;

    @Column(name = "user_id", nullable = false)
    private String userId;

    @Column(name = "date", nullable = false)
    private Date date;

    public UserStudyDailyStatsId() {
    }

    public UserStudyDailyStatsId(String userId, Date date) {
        this.userId = userId;
        this.date = date;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public Date getDate() {
        return date;
    }

    public void setDate(Date date) {
        this.date = date;
    }

    @Override
    public boolean equals(Object other) {
        if ((this == other))
            return true;
        if ((other == null))
            return false;
        if (!(other instanceof UserStudyDailyStatsId))
            return false;
        UserStudyDailyStatsId castOther = (UserStudyDailyStatsId) other;

        return this.userId.equals(castOther.userId) && this.date.equals(castOther.date);
    }

    @Override
    public int hashCode() {
        int result = 17;
        result = 37 * result + userId.hashCode();
        result = 37 * result + date.hashCode();
        return result;
    }
}
