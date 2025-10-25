package beidanci.api.model;

import java.util.List;

public class StudyGroupVo extends UuidVo {

    private StudyGroupGradeVo studyGroupGrade;
    private UserVo creator;

    private StudyGroupSummary groupSummary;

    private String groupName;

    private String groupTitle;

    private String groupRemark;

    private List<UserVo> users;

    private List<UserVo> managers;

    private Integer cowDung;

    private Integer todaysDakaCount;

    public Integer getTodaysDakaCount() {
        return todaysDakaCount;
    }

    public void setTodaysDakaCount(Integer todaysDakaCount) {
        this.todaysDakaCount = todaysDakaCount;
    }

    private List<StudyGroupPostVo> studyGroupPosts;


    public StudyGroupGradeVo getStudyGroupGrade() {
        return studyGroupGrade;
    }

    public void setStudyGroupGrade(StudyGroupGradeVo studyGroupGrade) {
        this.studyGroupGrade = studyGroupGrade;
    }

    public UserVo getCreator() {
        return creator;
    }

    public void setCreator(UserVo creator) {
        this.creator = creator;
    }

    public String getGroupName() {
        return groupName;
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

    public List<UserVo> getUsers() {
        return users;
    }

    public void setUsers(List<UserVo> users) {
        this.users = users;
    }

    public List<UserVo> getManagers() {
        return managers;
    }

    public void setManagers(List<UserVo> managers) {
        this.managers = managers;
    }

    public Integer getCowDung() {
        return cowDung;
    }

    public void setCowDung(Integer cowDung) {
        this.cowDung = cowDung;
    }

    public List<StudyGroupPostVo> getStudyGroupPosts() {
        return studyGroupPosts;
    }

    public void setStudyGroupPosts(List<StudyGroupPostVo> studyGroupPosts) {
        this.studyGroupPosts = studyGroupPosts;
    }

    public StudyGroupSummary getGroupSummary() {
        return groupSummary;
    }

    public void setGroupSummary(StudyGroupSummary groupSummary) {
        this.groupSummary = groupSummary;
    }
}
