package beidanci.api.model;

import java.util.List;

public class GetGameHallDataResult extends Vo {
    List<HallGroupVo> hallGroups;
    List<HallVo> halls;
    List<UserGameVo> topUserGames;

    public GetGameHallDataResult() {
    }

    public List<UserGameVo> getTopUserGames() {
        return topUserGames;
    }

    public void setTopUserGames(List<UserGameVo> topUserGames) {
        this.topUserGames = topUserGames;
    }

    public List<HallGroupVo> getHallGroups() {
        return hallGroups;
    }

    public void setHallGroups(List<HallGroupVo> hallGroups) {
        this.hallGroups = hallGroups;
    }

    public List<HallVo> getHalls() {
        return halls;
    }

    public void setHalls(List<HallVo> halls) {
        this.halls = halls;
    }
}
