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
        return getSynonymsOfDictBySeqRange(dictId, null, null);
    }

    public List<SynonymDto> getSynonymsOfDictBySeqRange(String dictId, Integer fromSeq, Integer toSeq) {
        StringBuilder sql = new StringBuilder("SELECT s.meaning_item_id, s.word_id, s.create_time, s.update_time, w.spell " +
                     "FROM synonym s LEFT JOIN word w ON w.id=s.word_id " +
                     "WHERE s.meaning_item_id IN (SELECT mi.id FROM meaning_item mi ");
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        
        if (fromSeq != null || toSeq != null) {
            sql.append("INNER JOIN dict_word dw ON dw.dict_id = mi.dict_id AND dw.word_id = mi.word_id ");
        }
        
        sql.append("WHERE mi.dict_id = :dictId");

        if (fromSeq != null) {
            sql.append(" AND dw.seq >= :fromSeq");
            params.addValue("fromSeq", fromSeq);
        }
        if (toSeq != null) {
            sql.append(" AND dw.seq <= :toSeq");
            params.addValue("toSeq", toSeq);
        }
        sql.append(")");

        String querySql = java.util.Objects.requireNonNull(sql.toString());
        return namedParameterJdbcTemplate.query(querySql, params, (rs, rowNum) -> {
            SynonymDto synonymDto = new SynonymDto();
            String meaningItemIdStr = rs.getString("meaning_item_id");
            assert meaningItemIdStr != null;
            synonymDto.setMeaningItemId(meaningItemIdStr);
            String wordIdStr = rs.getString("word_id");
            assert wordIdStr != null;
            synonymDto.setWordId(wordIdStr);
            synonymDto.setCreateTime(rs.getTimestamp("create_time"));
            synonymDto.setUpdateTime(rs.getTimestamp("update_time"));
            synonymDto.setSpell(rs.getString("spell"));
            return synonymDto;
        });
    }

    public void deleteByMeaningItem(String meaningItemId) {
        String sql = "DELETE FROM synonym WHERE meaning_item_id = :meaningItemId";
        MapSqlParameterSource params = new MapSqlParameterSource("meaningItemId", meaningItemId);
        namedParameterJdbcTemplate.update(sql, params);
    }
}
