package beidanci.service.po;

import java.util.List;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

@Entity
@Table(name = "study_group_grade")
public class StudyGroupGrade extends UuidPo {

    @Column(name = "name", nullable = false, unique = true)
    private String name;

    @Column(name = "max_user_count", nullable = false)
    private Integer maxUserCount;

    private List<StudyGroup> studyGroups;

    // Constructors

    /**
     * default constructor
     */
    public StudyGroupGrade() {
    }

    /**
     * minimal constructor
     */
    public StudyGroupGrade(String id, String name, Integer maxUserCount) {
        this.id = id;
        this.name = name;
        this.maxUserCount = maxUserCount;
    }

    public String getName() {
        return this.name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public Integer getMaxUserCount() {
        return this.maxUserCount;
    }

    public void setMaxUserCount(Integer maxUserCount) {
        this.maxUserCount = maxUserCount;
    }

    public List<StudyGroup> getStudyGroups() {
        return studyGroups;
    }

    public void setStudyGroups(List<StudyGroup> studyGroups) {
        this.studyGroups = studyGroups;
    }
}
