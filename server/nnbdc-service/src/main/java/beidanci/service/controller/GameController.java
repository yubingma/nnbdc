package beidanci.service.controller;

import beidanci.api.model.GetGameHallDataResult;
import beidanci.api.model.HallGroupVo;
import beidanci.api.model.HallVo;
import beidanci.api.model.UserGameVo;
import beidanci.service.bo.HallGroupBo;
import beidanci.service.bo.UserGameBo;
import beidanci.service.po.HallGroup;
import beidanci.service.po.UserGame;
import beidanci.service.socket.system.game.russia.Hall;
import beidanci.service.socket.system.game.russia.Russia;
import beidanci.service.util.BeanUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

@RestController
public class GameController {
    @Autowired
    Russia russia;

    @Autowired
    UserGameBo userGameBo;

    @Autowired
    HallGroupBo hallGroupBo;

    @PreAuthorize("hasAnyRole('USER', 'ADMIN')")
    @GetMapping("getGameHallData.do")
    public GetGameHallDataResult getGameHallData() throws IllegalAccessException {
        GetGameHallDataResult result = new GetGameHallDataResult();

        // 获取所有游戏大厅分组
        List<HallGroup> groups = hallGroupBo.queryAll(null, false);
        groups.sort(Comparator.comparingInt(HallGroup::getDisplayOrder));
        List<HallGroupVo> groupVos = BeanUtils.makeVos(groups, HallGroupVo.class,
                new String[]{"hallGroup", "dicts", "allDicts"});
        result.setHallGroups(groupVos);

        // 获取所有游戏大厅
        Map<String, Hall> halls = russia.getGameHalls();
        List<HallVo> hallVos = new ArrayList<>();
        for (Hall hall : halls.values()) {
            HallVo hallVo = new HallVo(hall.getName(), hall.getUserCount(), hall.getSystem().getName());
            hallVos.add(hallVo);
        }
        result.setHalls(hallVos);

        // 获取游戏积分榜
        List<UserGame> userGames = userGameBo.getUserGamesWithTopScore(15);
        List<UserGameVo> userGameVos = BeanUtils.makeVos(userGames, UserGameVo.class,
                new String[]{"studyGroups", "userGames"});
        result.setTopUserGames(userGameVos);
        for (UserGameVo userGameVo : userGameVos) {
            BeanUtils.setPropertiesToNull(userGameVo.getUser(), new String[]{"displayNickName", "id", "userName"});
        }

        return result;
    }
}
