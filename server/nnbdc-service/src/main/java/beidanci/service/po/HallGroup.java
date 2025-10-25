package beidanci.service.po;

import java.util.List;

import javax.persistence.CascadeType;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.FetchType;
import javax.persistence.OneToMany;
import javax.persistence.OrderBy;
import javax.persistence.Table;

@Entity
@Table(name = "hall_group")
public class HallGroup extends UuidPo {

    @Column(name = "gameType", length = 100)
    private String gameType;

    @Column(name = "groupName", length = 100)
    private String groupName;

    @Column(name = "displayOrder", nullable = false)
    private Integer displayOrder;

    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE}, mappedBy = "hallGroup", fetch = FetchType.LAZY)
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
