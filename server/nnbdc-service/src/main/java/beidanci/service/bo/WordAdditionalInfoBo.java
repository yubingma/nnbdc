package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.WordAdditionalInfo;

@Service
@Transactional(rollbackFor = Throwable.class)
public class WordAdditionalInfoBo extends BaseBo<WordAdditionalInfo> {
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<WordAdditionalInfo>() {
        });
    }

    public List<WordAdditionalInfo> findByWordSpell(String wordSpell) {
        String sql = "SELECT wai.* FROM word_additional_info wai INNER JOIN word w ON wai.wordId = w.id WHERE w.spell = :spell";
        MapSqlParameterSource params = new MapSqlParameterSource("spell", wordSpell);
        return namedParameterJdbcTemplate.query(sql, params, 
            new beidanci.service.dao.EntityRowMapper<>(WordAdditionalInfo.class));
    }
}
