package beidanci.service.bo;

import javax.annotation.PostConstruct;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.CannotAcquireLockException;
import org.springframework.dao.DeadlockLoserDataAccessException;
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
    private static final Logger log = LoggerFactory.getLogger(EventBo.class);

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

    /**
     * 删除与某个配图关联的所有事件记录。
     *
     * 说明：线上偶发会出现 event 行锁等待超时/死锁，当前策略是“单次尝试 + 失败返回”，
     * 由上层决定是否降级处理（例如末位淘汰时临时放宽限制）。
     */
    public boolean deleteEventsByWordImageId(String wordImageId) {
        if (wordImageId == null) {
            return true;
        }
        String sql = "DELETE FROM event WHERE wordImageId = :wordImageId";
        MapSqlParameterSource params = new MapSqlParameterSource("wordImageId", wordImageId);

        try {
            namedParameterJdbcTemplate.update(sql, params);
            return true;
        } catch (CannotAcquireLockException | DeadlockLoserDataAccessException ex) {
            log.warn("删除 event 记录失败（可能锁等待/死锁），wordImageId={}", wordImageId, ex);
            return false;
        }
    }
}
