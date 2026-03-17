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
        String sql = "SELECT s.meaning_item_id, s.word_id, s.create_time, s.update_time, w.spell FROM synonym s LEFT JOIN word w ON w.id=s.word_id WHERE s.meaning_item_id IN (SELECT mi.id FROM meaning_item mi WHERE mi.dict_id=:dictId)";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        List<SynonymDto> synonymDtos = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            SynonymDto synonymDto = new SynonymDto();
            synonymDto.setMeaningItemId(rs.getString("meaning_item_id"));
            synonymDto.setWordId(rs.getString("word_id"));
            synonymDto.setCreateTime(rs.getTimestamp("create_time"));
            synonymDto.setUpdateTime(rs.getTimestamp("update_time"));
            synonymDto.setSpell(rs.getString("spell"));
            return synonymDto;
        });

        return synonymDtos;
    }

    public void deleteByMeaningItem(String meaningItemId) {
        String sql = "DELETE FROM synonym WHERE meaning_item_id = :meaningItemId";
        MapSqlParameterSource params = new MapSqlParameterSource("meaningItemId", meaningItemId);
        namedParameterJdbcTemplate.update(sql, params);
    }
}
