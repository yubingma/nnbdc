package beidanci.service.bo;
import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.LoginLog;
import beidanci.service.po.User;

@Service
@Transactional(rollbackFor = Throwable.class)
public class LoginLogBo extends BaseBo<LoginLog> {
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<LoginLog>() {
        });
    }

    public void cleanLoginLogs(User user) {
        // 后面的单词前移
        String sql = "DELETE FROM login_log WHERE userId = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", user.getId());
        namedParameterJdbcTemplate.update(sql, params);
    }
}
