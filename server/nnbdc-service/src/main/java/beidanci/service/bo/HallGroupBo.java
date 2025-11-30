package beidanci.service.bo;

import javax.annotation.PostConstruct;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.DictGroup;
import beidanci.service.po.GameHall;
import beidanci.service.po.HallGroup;

@Service
@Transactional(rollbackFor = Throwable.class)
public class HallGroupBo extends BaseBo<HallGroup> {
    @PostConstruct
    public void init() {
        setDao(new BaseDao<HallGroup>() {
        });
    }

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    /**
     * 批量加载 HallGroup 的 gameHalls 集合
     */
    public void loadGameHallsForHallGroups(List<HallGroup> hallGroups) {
        if (hallGroups == null || hallGroups.isEmpty()) {
            return;
        }

        // 收集所有 HallGroup 的 ID
        Set<String> hallGroupIds = hallGroups.stream()
                .map(HallGroup::getId)
                .collect(Collectors.toSet());

        if (hallGroupIds.isEmpty()) {
            return;
        }

        // 查询所有属于这些 HallGroup 的 GameHall
        String sql = "SELECT * FROM game_hall WHERE hallGroupId IN (:hallGroupIds) ORDER BY displayOrder ASC";
        MapSqlParameterSource params = new MapSqlParameterSource("hallGroupIds", new ArrayList<>(hallGroupIds));
        List<GameHall> gameHalls = namedParameterJdbcTemplate.query(sql, params,
                new EntityRowMapper<>(GameHall.class));

        // 批量加载 DictGroup 对象
        loadDictGroupsForGameHalls(gameHalls);

        // 按 hallGroupId 分组
        Map<String, List<GameHall>> gameHallsByHallGroupId = new HashMap<>();
        for (GameHall gameHall : gameHalls) {
            // 从 hallGroup 关联对象中提取 ID
            if (gameHall.getHallGroup() != null) {
                String hallGroupId = gameHall.getHallGroup().getId();
                gameHallsByHallGroupId.computeIfAbsent(hallGroupId, k -> new ArrayList<>()).add(gameHall);
            }
        }

        // 为每个 HallGroup 设置 gameHalls
        for (HallGroup hallGroup : hallGroups) {
            List<GameHall> groupGameHalls = gameHallsByHallGroupId.getOrDefault(hallGroup.getId(), new ArrayList<>());
            hallGroup.setGameHalls(groupGameHalls);
        }
    }

    /**
     * 批量加载 GameHall 的 dictGroup 对象
     */
    private void loadDictGroupsForGameHalls(List<GameHall> gameHalls) {
        if (gameHalls == null || gameHalls.isEmpty()) {
            return;
        }

        // 收集所有 dictGroupId
        Set<String> dictGroupIds = new java.util.HashSet<>();
        for (GameHall gameHall : gameHalls) {
            if (gameHall.getDictGroup() != null && gameHall.getDictGroup().getId() != null) {
                dictGroupIds.add(gameHall.getDictGroup().getId());
            }
        }

        if (dictGroupIds.isEmpty()) {
            return;
        }

        // 批量查询 DictGroup
        String sql = "SELECT * FROM dict_group WHERE id IN (:ids)";
        MapSqlParameterSource params = new MapSqlParameterSource("ids", new ArrayList<>(dictGroupIds));
        List<DictGroup> dictGroups = namedParameterJdbcTemplate.query(sql, params,
                new EntityRowMapper<>(DictGroup.class));

        Map<String, DictGroup> dictGroupMap = dictGroups.stream()
                .collect(Collectors.toMap(DictGroup::getId, dg -> dg));

        // 为每个 GameHall 设置完整的 DictGroup 对象
        for (GameHall gameHall : gameHalls) {
            if (gameHall.getDictGroup() != null && gameHall.getDictGroup().getId() != null) {
                DictGroup fullDictGroup = dictGroupMap.get(gameHall.getDictGroup().getId());
                if (fullDictGroup != null) {
                    gameHall.setDictGroup(fullDictGroup);
                }
            }
        }
    }
}
