package beidanci.api.model;

public class StudyGroupGradeVo extends UuidVo {

    private String name;

    private Integer maxUserCount;


    public void setName(String name) {
        this.name = name;
    }

    public Integer getMaxUserCount() {
        return maxUserCount;
    }

    public void setMaxUserCount(Integer maxUserCount) {
        this.maxUserCount = maxUserCount;
    }

    public String getName() {
        return name;
    }

}
