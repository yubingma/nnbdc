package beidanci.service.po;

import java.text.ParseException;
import java.util.Date;
import java.util.List;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.OrderBy;
import javax.persistence.Table;

import beidanci.api.model.StudyGroupSummary;

@Entity
@Table(name = "study_group")
public class StudyGroup extends UuidPo  {

    @Column(name = "studyGroupGradeId")
    private StudyGroupGrade studyGroupGrade;

    @Column(name = "creatorId")
    private User creator;

    @Column(name = "groupName", length = 100, nullable = false, unique = true)
    private String groupName;

    @Column(name = "groupTitle", length = 100, nullable = false)
    private String groupTitle;

    @Column(name = "groupRemark", length = 4000, nullable = false)
    private String groupRemark;

    private  List<User> users;

    private   List<User> managers;

    @Column(name = "cowDung", nullable = false)
    private Integer cowDung;

    private   List<StudyGroupSnapshotDaily> snapshotDailys;

    @OrderBy("updateTime desc")
    private   List<StudyGroupPost> studyGroupPosts;

    // Constructors

    /**
     * default constructor
     */
    public StudyGroup() {
    }

    /**
     * minimal constructor
     */
    public StudyGroup(String id, StudyGroupGrade studyGroupGrade, User creator, String groupName) {
        this.id = id;
        this.studyGroupGrade = studyGroupGrade;
        this.creator = creator;
        this.groupName = groupName;
    }

    /**
     * full constructor
     */
    public StudyGroup(String id, StudyGroupGrade studyGroupGrade, User creator, String groupName, List<User> users,
                      List<User> managers) {
        this.id = id;
        this.studyGroupGrade = studyGroupGrade;
        this.creator = creator;
        this.groupName = groupName;
        this.users = users;
        this.managers = managers;
    }

    // Property accessors


    public StudyGroupGrade getStudyGroupGrade() {
        return this.studyGroupGrade;
    }

    public void setStudyGroupGrade(StudyGroupGrade studyGroupGrade) {
        this.studyGroupGrade = studyGroupGrade;
    }

    public User getCreator() {
        return this.creator;
    }

    public void setCreator(User creator) {
        this.creator = creator;
    }

    public String getGroupName() {
        return this.groupName;
    }

    public void setGroupName(String groupName) {
        this.groupName = groupName;
    }

    public String getGroupTitle() {
        return groupTitle;
    }

    public void setGroupTitle(String groupTitle) {
        this.groupTitle = groupTitle;
    }

    public String getGroupRemark() {
        return groupRemark;
    }

    public void setGroupRemark(String groupRemark) {
        this.groupRemark = groupRemark;
    }

    public Integer getCowDung() {
        return cowDung;
    }

    public void setCowDung(Integer cowDung) {
        this.cowDung = cowDung;
    }

    /**
     * 判断小组是否是懒人小组。懒人小组是指：创立时间大于10天，且打卡率小于80%
     * 注意：此方法需要 StudyGroupBo.getGroupSummary() 来计算打卡率
     *
     * @return
     */
    public boolean isBadGroup(StudyGroupSummary summary) throws ParseException {
        return (new Date().getTime() - getCreateTime().getTime()) > 10 * 24 * 60 * 60 * 1000
                && summary.getDakaRatio() < 0.8;
    }


    public List<User> getUsers() {
        return users;
    }

    public void setUsers(List<User> users) {
        this.users = users;
    }

    public List<User> getManagers() {
        return managers;
    }

    public void setManagers(List<User> managers) {
        this.managers = managers;
    }

    public List<StudyGroupSnapshotDaily> getSnapshotDailys() {
        return snapshotDailys;
    }

    public void setSnapshotDailys(List<StudyGroupSnapshotDaily> snapshotDailys) {
        this.snapshotDailys = snapshotDailys;
    }

    public List<StudyGroupPost> getStudyGroupPosts() {
        return studyGroupPosts;
    }

    public void setStudyGroupPosts(List<StudyGroupPost> studyGroupPosts) {
        this.studyGroupPosts = studyGroupPosts;
    }
}
