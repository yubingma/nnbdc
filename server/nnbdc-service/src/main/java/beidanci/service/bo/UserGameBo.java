package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
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
                "INNER JOIN user u ON ug.userId = u.id " +
                "WHERE u.userName NOT LIKE 'guest%' AND u.userName NOT LIKE 'guess%' AND u.userName NOT LIKE '游客%' " +
                "ORDER BY ug.Score DESC LIMIT :count";
        MapSqlParameterSource params = new MapSqlParameterSource("count", count);
        return namedParameterJdbcTemplate.query(sql, params, 
            new beidanci.service.dao.EntityRowMapper<>(UserGame.class));
    }

    /**
     * 获取某用户的所有游戏记录。JDBC 不需要管理 Session。
     */
    public List<UserGame> getUserGamesOfUser(String userId, boolean openNewSession) {
        // JDBC 不需要管理 Session，openNewSession 参数保留以保持接口兼容性
        String sql = "SELECT * FROM user_game WHERE userId = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        return namedParameterJdbcTemplate.query(sql, params, 
            new beidanci.service.dao.EntityRowMapper<>(UserGame.class));
    }

}
