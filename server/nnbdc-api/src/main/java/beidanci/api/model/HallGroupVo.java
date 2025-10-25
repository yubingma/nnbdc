package beidanci.api.model;

import java.util.List;

public class HallGroupVo extends UuidVo {

    private String gameType;

    private String groupName;

    private Integer displayOrder;

    private List<GameHallVo> gameHalls;

    private int userCount;

    public int getUserCount() {
        return userCount;
    }

    public void setUserCount(int userCount) {
        this.userCount = userCount;
    }


    public String getGameType() {
        return gameType;
    }

    public void setGameType(String gameType) {
        this.gameType = gameType;
    }

    public String getGroupName() {
        return groupName;
    }

    public void setGroupName(String groupName) {
        this.groupName = groupName;
    }

    public Integer getDisplayOrder() {
        return displayOrder;
    }

    public void setDisplayOrder(Integer displayOrder) {
        this.displayOrder = displayOrder;
    }

    public List<GameHallVo> getGameHalls() {
        return gameHalls;
    }

    public void setGameHalls(List<GameHallVo> gameHalls) {
        this.gameHalls = gameHalls;
    }
}
