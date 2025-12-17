package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.User;
import beidanci.service.po.UserGame;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserGameBo extends BaseBo<UserGame> {
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<UserGame>() {
        });
    }

    public List<UserGame> getUserGamesWithTopScore(final int count) {
        String sql = "SELECT ug.* FROM user_game ug " +
                "INNER JOIN user u ON ug.user_id = u.id " +
                "WHERE u.user_name NOT LIKE 'guest%' AND u.user_name NOT LIKE 'guess%' AND u.user_name NOT LIKE '游客%' " +
                "ORDER BY ug.Score DESC LIMIT :count";
        MapSqlParameterSource params = new MapSqlParameterSource("count", count);
        List<UserGame> userGames = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(UserGame.class));
        
        // 批量加载完整的 User 对象，填充 user 字段
        loadUsersForUserGames(userGames);
        
        return userGames;
    }

    /**
     * 获取某用户的所有游戏记录。JDBC 不需要管理 Session。
     */
    public List<UserGame> getUserGamesOfUser(String userId, boolean openNewSession) {
        // JDBC 不需要管理 Session，openNewSession 参数保留以保持接口兼容性
        String sql = "SELECT * FROM user_game WHERE user_id = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        List<UserGame> userGames = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(UserGame.class));
        
        // 批量加载完整的 User 对象，填充 user 字段
        loadUsersForUserGames(userGames);
        
        return userGames;
    }
    
    /**
     * 批量加载 User 对象并填充到 UserGame 的 user 字段
     */
    private void loadUsersForUserGames(List<UserGame> userGames) {
        if (userGames == null || userGames.isEmpty()) {
            return;
        }
        
        // 收集所有需要加载的 User ID
        Set<String> userIds = new HashSet<>();
        for (UserGame userGame : userGames) {
            if (userGame.getUser() != null && userGame.getUser().getId() != null) {
                userIds.add(userGame.getUser().getId());
            }
        }
        
        if (userIds.isEmpty()) {
            return;
        }
        
        // 批量查询 User 对象
        String sql = "SELECT * FROM user WHERE id IN (:ids)";
        MapSqlParameterSource params = new MapSqlParameterSource("ids", userIds);
        List<User> users = namedParameterJdbcTemplate.query(sql, params,
            new EntityRowMapper<>(User.class));
        
        // 构建 User ID 到 User 对象的映射
        Map<String, User> userMap = new HashMap<>();
        for (User user : users) {
            userMap.put(user.getId(), user);
        }
        
        // 填充 UserGame 的 user 字段
        for (UserGame userGame : userGames) {
            if (userGame.getUser() != null && userGame.getUser().getId() != null) {
                User fullUser = userMap.get(userGame.getUser().getId());
                if (fullUser != null) {
                    userGame.setUser(fullUser);
                }
            }
        }
    }

}
