package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.FetchType;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

@Entity
@Table(name = "study_group_snapshot_daily")
public class StudyGroupSnapshotDaily extends UuidPo {


    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "groupId")
    private StudyGroup studyGroup;

    @Column(name = "theDate", nullable = false)
    private Date theDate;

    @Column(name = "memberCount", nullable = false)
    private Integer memberCount;

    @Column(name = "orderNo", nullable = false)
    private Integer orderNo;

    @Column(name = "cowDung", nullable = false)
    private Integer cowDung;

    @Column(name = "dakaScore", nullable = false)
    private Integer dakaScore;

    @Column(name = "dakaRatio", nullable = false)
    private Float dakaRatio;

    @Column(name = "gameScore", nullable = false)
    private Integer gameScore;

    // Constructors

    /**
     * default constructor
     */
    public StudyGroupSnapshotDaily() {
    }

    public StudyGroup getStudyGroup() {
        return this.studyGroup;
    }

    public void setStudyGroup(StudyGroup studyGroup) {
        this.studyGroup = studyGroup;
    }

    public Date getTheDate() {
        return this.theDate;
    }

    public void setTheDate(Date theDate) {
        this.theDate = theDate;
    }

    public Integer getMemberCount() {
        return this.memberCount;
    }

    public void setMemberCount(Integer memberCount) {
        this.memberCount = memberCount;
    }

    public Integer getOrderNo() {
        return this.orderNo;
    }

    public void setOrderNo(Integer orderNo) {
        this.orderNo = orderNo;
    }

    public Integer getCowDung() {
        return this.cowDung;
    }

    public void setCowDung(Integer cowDung) {
        this.cowDung = cowDung;
    }

    public Integer getDakaScore() {
        return this.dakaScore;
    }

    public void setDakaScore(Integer dakaScore) {
        this.dakaScore = dakaScore;
    }

    public Float getDakaRatio() {
        return this.dakaRatio;
    }

    public void setDakaRatio(Float dakaRatio) {
        this.dakaRatio = dakaRatio;
    }

    public Integer getGameScore() {
        return this.gameScore;
    }

    public void setGameScore(Integer gameScore) {
        this.gameScore = gameScore;
    }

}
