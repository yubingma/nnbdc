package beidanci.api.model;

public class HallVo extends Vo {
    private String name;

    public int getUserCount() {
        return userCount;
    }

    private final int userCount;

    public HallVo(String name, int userCount, String system) {
        this.name = name;
        this.userCount = userCount;
        this.system = system;
    }

    private String system;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getSystem() {
        return system;
    }

    public void setSystem(String system) {
        this.system = system;
    }
}
