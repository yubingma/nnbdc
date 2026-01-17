package beidanci.service.bo;

import java.util.Date;
import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.UserDbLog;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserDbLogBo extends BaseBo<UserDbLog> {
        @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<UserDbLog>() {
        });
    }

    /**
     * 清理旧日志（保留最近30天）
     * 建议通过定时任务调用
     */
    public int cleanOldLogs() {
        Date thirtyDaysAgo = new Date(System.currentTimeMillis() - 30L * 24 * 60 * 60 * 1000);
        String sql = "DELETE FROM user_db_log WHERE create_time < :date";
        MapSqlParameterSource params = new MapSqlParameterSource("date", thirtyDaysAgo);
        return namedParameterJdbcTemplate.update(sql, params);
    }
}
