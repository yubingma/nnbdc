package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.CigenWordLink;

@Service
@Transactional(rollbackFor = Throwable.class)
public class CigenWordLinkBo extends BaseBo<CigenWordLink> {
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<CigenWordLink>() {
        });
    }

    public List<CigenWordLink> findByWordId(String wordId) {
        String sql = "SELECT * FROM cigen_word_link WHERE wordId = :wordId";
        MapSqlParameterSource params = new MapSqlParameterSource("wordId", wordId);
        return namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(CigenWordLink.class));
    }


}
