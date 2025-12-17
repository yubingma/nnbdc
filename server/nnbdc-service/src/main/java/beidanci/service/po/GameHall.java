package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

@Entity
@Table(name = "game_hall")
public class GameHall extends UuidPo  {

    @Column(name = "game_type", nullable = false)
    private String gameType;

    @Column(name = "hall_name", nullable = false)
    private String hallName;

    @Column(name = "dict_group_id")
    private DictGroup dictGroup;

    @Column(name = "hall_group_id")
    private HallGroup hallGroup;

    @Column(name = "base_point")
    private Integer basePoint;

    @Column(name = "display_order")
    private Integer displayOrder;

    // Constructors

    /**
     * default constructor
     */
    public GameHall() {
    }

    public DictGroup getDictGroup() {
        return this.dictGroup;
    }

    public void setDictGroup(DictGroup dictGroup) {
        this.dictGroup = dictGroup;
    }

    public HallGroup getHallGroup() {
        return this.hallGroup;
    }

    public void setHallGroup(HallGroup hallGroup) {
        this.hallGroup = hallGroup;
    }

    public Integer getBasePoint() {
        return this.basePoint;
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

    public void setBasePoint(Integer basePoint) {
        this.basePoint = basePoint;
    }

    public Integer getDisplayOrder() {
        return this.displayOrder;
    }

    public void setDisplayOrder(Integer displayOrder) {
        this.displayOrder = displayOrder;
    }


}
