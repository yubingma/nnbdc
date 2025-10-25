package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

@Entity
@Table(name = "game_hall")
public class GameHall extends UuidPo  {

    @Column(name = "gameType", nullable = false)
    private String gameType;

    @Column(name = "hallName", nullable = false)
    private String hallName;

    @ManyToOne
    @JoinColumn(name = "dictGroupId", nullable = false, updatable = false, insertable = false)
    private DictGroup dictGroup;

    @ManyToOne
    @JoinColumn(name = "hallGroupId", nullable = false, insertable = false, updatable = false)
    private HallGroup hallGroup;

    @Column(name = "basePoint")
    private Integer basePoint;

    @Column(name = "displayOrder")
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
