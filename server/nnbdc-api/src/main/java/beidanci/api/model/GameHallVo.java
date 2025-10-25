package beidanci.api.model;

public class GameHallVo extends UuidVo {

    private String gameType;

    private String hallName;

    private DictGroupVo dictGroup;

    private HallGroupVo hallGroup;

    private Integer basePoint;

    private Integer displayOrder;

    private int userCount;

    public int getUserCount() {
        return userCount;
    }

    public void setUserCount(int userCount) {
        this.userCount = userCount;
    }

    public DictGroupVo getDictGroup() {
        return dictGroup;
    }

    public void setDictGroup(DictGroupVo dictGroup) {
        this.dictGroup = dictGroup;
    }

    public HallGroupVo getHallGroup() {
        return hallGroup;
    }

    public void setHallGroup(HallGroupVo hallGroup) {
        this.hallGroup = hallGroup;
    }

    public Integer getBasePoint() {
        return basePoint;
    }

    public void setBasePoint(Integer basePoint) {
        this.basePoint = basePoint;
    }

    public Integer getDisplayOrder() {
        return displayOrder;
    }

    public void setDisplayOrder(Integer displayOrder) {
        this.displayOrder = displayOrder;
    }

    public String getGameType() {
        return gameType;
    }

    public void setGameType(String gameType) {
        this.gameType = gameType;
    }

    public String getHallName() {
        return hallName;
    }

    public void setHallName(String hallName) {
        this.hallName = hallName;
    }

}
