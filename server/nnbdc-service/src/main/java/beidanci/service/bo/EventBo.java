package beidanci.service.bo;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.Event;
import beidanci.service.po.User;

@Service
@Transactional(rollbackFor = Throwable.class)
public class EventBo extends BaseBo<Event> {
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<Event>() {
        });
    }

    public void clearUserEvents(User user) {
        String sql = "DELETE FROM event WHERE userId = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", user.getId());
        namedParameterJdbcTemplate.update(sql, params);
    }
}
