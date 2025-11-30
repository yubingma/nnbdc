package beidanci.service.bo;
import java.util.List;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.SynonymDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.Synonym;

@Service
@Transactional(rollbackFor = Throwable.class)
public class SynonymBo extends BaseBo<Synonym> {
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<Synonym>() {
        });
    }

    public List<SynonymDto> getSynonymsOfDict(String dictId) {
        // 通用词典现在是数据库中的实际记录，统一查询
        String sql = "SELECT s.meaningItemId, s.wordId, s.createTime, s.updateTime, w.spell FROM synonym s LEFT JOIN word w ON w.id=s.wordId WHERE s.meaningItemId IN (SELECT mi.id FROM meaning_item mi WHERE mi.dictId=:dictId)";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        List<SynonymDto> synonymDtos = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            SynonymDto synonymDto = new SynonymDto();
            synonymDto.setMeaningItemId(rs.getString("meaningItemId"));
            synonymDto.setWordId(rs.getString("wordId"));
            synonymDto.setCreateTime(rs.getTimestamp("createTime"));
            synonymDto.setUpdateTime(rs.getTimestamp("updateTime"));
            synonymDto.setSpell(rs.getString("spell"));
            return synonymDto;
        });

        return synonymDtos;
    }
}
