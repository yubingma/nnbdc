package beidanci.service.po;

import java.util.Date;
import java.util.Objects;

import javax.persistence.Column;
import javax.persistence.Embeddable;

import beidanci.util.Utils;

@Embeddable
public class UserStudyRecordId implements java.io.Serializable {

    private static final long serialVersionUID = 1L;


    @Column(name = "userId", nullable = false)
    private String userId;

    @Column(name = "theDate", nullable = false)
    private Date theDate;

    public Date getTheDate() {
        return theDate;
    }

    public String getUserId() {
        return userId;
    }

    public UserStudyRecordId() {
    }

    public UserStudyRecordId(String userId, Date theDate) {
        this.userId = userId;
        this.theDate = Utils.getPureDate(theDate);
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        UserStudyRecordId that = (UserStudyRecordId) o;
        return Objects.equals(userId, that.userId) && Objects.equals(theDate, that.theDate);
    }

    @Override
    public int hashCode() {
        return Objects.hash(userId, theDate);
    }
}
