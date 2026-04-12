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
     * 清理旧日志（保留最近10天）
     */
    public int cleanOldLogs() {
        Date cutoff = new Date(System.currentTimeMillis() - 10L * 24 * 60 * 60 * 1000);
        // 为确保版本完整性，如果一个版本中任何一条记录过期，则删除该版本的所有记录
        String sql = "DELETE FROM user_db_log " +
                "WHERE (user_id, version) IN (" +
                "  SELECT DISTINCT user_id, version FROM user_db_log WHERE create_time < :date" +
                ")";
        MapSqlParameterSource params = new MapSqlParameterSource("date", cutoff);
        return namedParameterJdbcTemplate.update(sql, params);
    }

    /**
     * 执行数据库维护 (VACUUM ANALYZE)
     * 该操作在 PostgreSQL 中可显著提升清理后的空间利用率和查询性能
     */
    public void vacuumAnalyze() {
        jdbcTemplate.execute("VACUUM ANALYZE user_db_log");
    }
}
