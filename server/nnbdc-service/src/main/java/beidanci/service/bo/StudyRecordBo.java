package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.Date;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.User;
import beidanci.service.po.UserStudyRecord;

@Service
@Transactional(rollbackFor = Throwable.class)
public class StudyRecordBo extends BaseBo<UserStudyRecord> {
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<UserStudyRecord>() {
        });
    }

    public List<UserStudyRecord> getStudyRecords(User user, Date startDate, Date endDate) {
        String sql = "SELECT * FROM user_study_record WHERE user_id = :userId AND the_date >= :startDate AND the_date <= :endDate";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("userId", user.getId());
        params.addValue("startDate", startDate);
        params.addValue("endDate", endDate);
        return namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(UserStudyRecord.class));
    }
}
