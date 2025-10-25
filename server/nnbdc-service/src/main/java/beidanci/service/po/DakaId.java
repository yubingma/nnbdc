package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Embeddable;

@Embeddable
public class DakaId implements java.io.Serializable {

    private static final long serialVersionUID = 1L;


    @Column(name = "userId", nullable = false)
    private String userId;

    @Column(name = "forLearningDate", nullable = false)
    private Date forLearningDate;

    // Constructors

    /**
     * default constructor
     */
    public DakaId() {
    }

    public DakaId(String userId, Date forLearningDate) {
        this.userId = userId;
        this.forLearningDate = forLearningDate;
    }

    public Date getForLearningDate() {
        return this.forLearningDate;
    }

    public void setForLearningDate(Date forLearningDate) {
        this.forLearningDate = forLearningDate;
    }

    @Override
    public boolean equals(Object other) {
        if ((this == other))
            return true;
        if ((other == null))
            return false;
        if (!(other instanceof DakaId))
            return false;
        DakaId castOther = (DakaId) other;

        return this.userId.equals(castOther.userId) && this.forLearningDate.equals(castOther.forLearningDate);
    }

    @Override
    public int hashCode() {
        int result = 17;

        result = 37 * result + userId.hashCode();
        result = 37 * result + forLearningDate.hashCode();
        return result;
    }

}
