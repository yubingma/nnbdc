package beidanci.service.po;

import java.util.List;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.OrderBy;
import javax.persistence.Table;

@Entity
@Table(name = "hall_group")
public class HallGroup extends UuidPo {

    @Column(name = "game_type", length = 100)
    private String gameType;

    @Column(name = "group_name", length = 100)
    private String groupName;

    @Column(name = "display_order", nullable = false)
    private Integer displayOrder;

    @OrderBy("displayOrder asc")
    private List<GameHall> gameHalls;

    /**
     * default constructor
     */
    public HallGroup() {
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
        return this.displayOrder;
    }

    public void setDisplayOrder(Integer displayOrder) {
        this.displayOrder = displayOrder;
    }

    public List<GameHall> getGameHalls() {
        return this.gameHalls;
    }

    public void setGameHalls(List<GameHall> gameHalls) {
        this.gameHalls = gameHalls;
    }

}
