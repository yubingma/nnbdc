package beidanci.service.bo;

import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.MeaningItemDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.MeaningItem;
import beidanci.service.util.Util;

@Service
@Transactional(rollbackFor = Throwable.class)
public class MeaningItemBo extends BaseBo<MeaningItem> {
    private static final org.slf4j.Logger logger = org.slf4j.LoggerFactory.getLogger(MeaningItemBo.class);
    
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<MeaningItem>() {
        });
    }

    /** 获取指定词书的所有单词释义项，通用词典ID为'0' */
    public List<MeaningItemDto> getMeaningItemsOfDict(String dictId) {
        return getMeaningItemsOfDictBySeqRange(dictId, null, null);
    }

    public List<MeaningItemDto> getMeaningItemsOfDictBySeqRange(String dictId, Integer fromSeq, Integer toSeq) {
        StringBuilder sql = new StringBuilder("SELECT mi.id, mi.ci_xing, mi.meaning, mi.word_id, mi.dict_id, mi.owner_id, mi.popularity, mi.popularity_percent, mi.create_time, mi.update_time, mi.is_updating, mi.updating_start_at " +
                     "FROM meaning_item mi ");
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

        String querySql = java.util.Objects.requireNonNull(sql.toString());
        return namedParameterJdbcTemplate.query(querySql, params, (rs, rowNum) -> {
            MeaningItemDto meaningItemDto = new MeaningItemDto();
            String idStr = rs.getString("id");
            assert idStr != null;
            meaningItemDto.setId(idStr);
            meaningItemDto.setCiXing(rs.getString("ci_xing"));
            meaningItemDto.setMeaning(rs.getString("meaning"));
            String wordIdStr = rs.getString("word_id");
            assert wordIdStr != null;
            meaningItemDto.setWordId(wordIdStr);
            String dictIdStr = rs.getString("dict_id");
            assert dictIdStr != null;
            meaningItemDto.setDictId(dictIdStr);
            Integer popularity = rs.getObject("popularity", Integer.class);
            meaningItemDto.setPopularity(popularity != null ? popularity : 999);
            meaningItemDto.setPopularityPercent(rs.getObject("popularity_percent", Integer.class));
            meaningItemDto.setCreateTime(rs.getTimestamp("create_time"));
            meaningItemDto.setUpdateTime(rs.getTimestamp("update_time"));
            meaningItemDto.setOwnerId(rs.getString("owner_id"));
            meaningItemDto.setUpdating(rs.getBoolean("is_updating"));
            meaningItemDto.setUpdatingStartAt(rs.getTimestamp("updating_start_at"));
            return meaningItemDto;
        });
    }

    public List<MeaningItemDto> findMeaningsByWord(String wordId) {
        String sql = "SELECT id, ci_xing, meaning, word_id, dict_id, owner_id, popularity, popularity_percent, create_time, update_time, is_updating, updating_start_at FROM meaning_item WHERE word_id = :wordId ORDER BY popularity ASC NULLS LAST, create_time ASC";
        MapSqlParameterSource params = new MapSqlParameterSource("wordId", wordId);

        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            MeaningItemDto dto = new MeaningItemDto();
            dto.setId(rs.getString("id"));
            dto.setCiXing(rs.getString("ci_xing"));
            dto.setMeaning(rs.getString("meaning"));
            dto.setWordId(rs.getString("word_id"));
            dto.setDictId(rs.getString("dict_id"));
            Integer popularity = rs.getObject("popularity", Integer.class);
            dto.setPopularity(popularity != null ? popularity : 999);
            dto.setPopularityPercent(rs.getObject("popularity_percent", Integer.class));
            dto.setCreateTime(rs.getTimestamp("create_time"));
            dto.setUpdateTime(rs.getTimestamp("update_time"));
            dto.setOwnerId(rs.getString("owner_id"));
            dto.setUpdating(rs.getBoolean("is_updating"));
            dto.setUpdatingStartAt(rs.getTimestamp("updating_start_at"));
            return dto;
        });
    }

    public List<MeaningItem> findEntitiesByWord(String wordId) {
        String sql = "SELECT * FROM meaning_item WHERE word_id = :wordId ORDER BY popularity ASC NULLS LAST, create_time ASC";
        MapSqlParameterSource params = new MapSqlParameterSource("wordId", wordId);
        return namedParameterJdbcTemplate.query(sql, params, new EntityRowMapper<>(MeaningItem.class));
    }

    public List<MeaningItemDto> findMeaningsByWordAndDict(String wordId, String dictId) {
        String sql = "SELECT id, ci_xing, meaning, word_id, dict_id, owner_id, popularity, popularity_percent, create_time, update_time, is_updating, updating_start_at FROM meaning_item WHERE word_id = :wordId AND dict_id = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("wordId", wordId);
        params.addValue("dictId", dictId);

        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            MeaningItemDto dto = new MeaningItemDto();
            dto.setId(rs.getString("id"));
            dto.setCiXing(rs.getString("ci_xing"));
            dto.setMeaning(rs.getString("meaning"));
            dto.setWordId(rs.getString("word_id"));
            dto.setDictId(rs.getString("dict_id"));
            Integer popularity = rs.getObject("popularity", Integer.class);
            dto.setPopularity(popularity != null ? popularity : 999);
            dto.setPopularityPercent(rs.getObject("popularity_percent", Integer.class));
            dto.setCreateTime(rs.getTimestamp("create_time"));
            dto.setUpdateTime(rs.getTimestamp("update_time"));
            dto.setOwnerId(rs.getString("owner_id"));
            dto.setUpdating(rs.getBoolean("is_updating"));
            dto.setUpdatingStartAt(rs.getTimestamp("updating_start_at"));
            return dto;
        });
    }

    /**
     * 为给定的 wordId 集合，从任意词典中各取一条释义作为兜底（仅当该词在通用词典中无释义时使用）。
     */
    public List<MeaningItemDto> getOneMeaningPerWordFromAnyDict(List<String> wordIds) {
        if (wordIds == null || wordIds.isEmpty()) {
            return new ArrayList<>();
        }

        // 使用原生SQL一次性取回所有候选，按 word 聚合取最后更新的那条
        String sql = "SELECT id, ci_xing, meaning, word_id, dict_id, owner_id, popularity, popularity_percent, create_time, update_time, is_updating, updating_start_at FROM meaning_item "
                + "WHERE word_id IN (:ids) ORDER BY update_time DESC";
        MapSqlParameterSource params = new MapSqlParameterSource("ids", wordIds);
        List<MeaningItemDto> allResults = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            MeaningItemDto dto = new MeaningItemDto();
            dto.setId(rs.getString("id"));
            dto.setCiXing(rs.getString("ci_xing"));
            dto.setMeaning(rs.getString("meaning"));
            dto.setWordId(rs.getString("word_id"));
            dto.setDictId(rs.getString("dict_id"));
            Integer popularity = rs.getObject("popularity", Integer.class);
            dto.setPopularity(popularity != null ? popularity : 999);
            dto.setPopularityPercent(rs.getObject("popularity_percent", Integer.class));
            dto.setCreateTime(rs.getTimestamp("create_time"));
            dto.setUpdateTime(rs.getTimestamp("update_time"));
            dto.setOwnerId(rs.getString("owner_id"));
            dto.setUpdating(rs.getBoolean("is_updating"));
            dto.setUpdatingStartAt(rs.getTimestamp("updating_start_at"));
            return dto;
        });

        List<MeaningItemDto> picked = new ArrayList<>();
        HashSet<String> seen = new HashSet<>();
        for (MeaningItemDto dto : allResults) {
            if (seen.contains(dto.getWordId())) {
                continue;
            }
            picked.add(dto);
            seen.add(dto.getWordId());
            if (seen.size() == wordIds.size()) {
                break;
            }
        }
        if (!picked.isEmpty()) {
            logger.info(String.format("【健康检查】为 %d 个单词找到了备选释义", picked.size()));
        } else {
            logger.info("【健康检查】未找到任何备选释义");
        }
        return picked;
    }

    /**
     * 补丁:
     * 在数据库中为缺失通用释义（dictId = '0'）的单词，补充一条通用释义。
     * 逻辑：从任意词典的释义中拷贝一条，写入为通用释义（dictId='0'）。
     * 仅补充缺失项（NOT EXISTS 保证幂等）。
     * 返回插入的行数。
     */
    public int supplementCommonMeanings() {
        String sql = "INSERT INTO meaning_item (id, ci_xing, meaning, word_id, dict_id, owner_id, popularity, create_time, update_time) "
                +
                "SELECT REPLACE(gen_random_uuid()::text, '-', ''), mi.ci_xing, mi.meaning, mi.word_id, '0', '15118', mi.popularity, NOW(), NOW() "
                +
                "FROM meaning_item mi " +
                "LEFT JOIN meaning_item cm ON cm.word_id = mi.word_id AND cm.dict_id = '0' " +
                "WHERE mi.dict_id != '0' AND cm.id IS NULL";
        return namedParameterJdbcTemplate.getJdbcTemplate().update(sql);
    }

    // ============================================
    // 系统健康检查相关方法
    // ============================================

    /**
     * 查找缺少释义项的单词
     */
    public List<String> findWordsWithoutMeanings(String dictId) {
        String sql = "SELECT dw.word_id " +
                "FROM dict_word dw " +
                "WHERE dw.dict_id = :dictId " +
                "AND dw.word_id NOT IN (" +
                "    SELECT mi.word_id " +
                "    FROM meaning_item mi " +
                "    WHERE mi.dict_id = :dictId" +
                ")";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> rs.getString("word_id"));
    }

    /**
     * 更新自定义词典中的单词释义（先删除该词在该词典下的所有现有释义，再插入新的）
     */
    public void updateMeanings(String dictId, String wordId, List<Map<String, String>> meanings, String ownerId) {
        // 1. 删除现有定制释义
        String deleteSql = "DELETE FROM meaning_item WHERE word_id = :wordId AND dict_id = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("wordId", wordId);
        params.addValue("dictId", dictId);
        namedParameterJdbcTemplate.update(deleteSql, params);

        // 2. 插入新释义
        if (meanings != null) {
            String insertSql = "INSERT INTO meaning_item (id, word_id, dict_id, owner_id, ci_xing, meaning, popularity, popularity_percent, create_time, update_time, is_updating) "
                    +
                    "VALUES (:id, :wordId, :dictId, :ownerId, :ciXing, :meaning, :popularity, :popularityPercent, :createTime, :updateTime, false)";
            Timestamp now = new Timestamp(System.currentTimeMillis());
            for (int i = 0; i < meanings.size(); i++) {
                Map<String, String> meaning = meanings.get(i);
                MapSqlParameterSource insertParams = new MapSqlParameterSource();
                insertParams.addValue("id", Util.uuid());
                insertParams.addValue("wordId", wordId);
                insertParams.addValue("dictId", dictId);
                insertParams.addValue("ownerId", ownerId != null ? ownerId : "15118"); 
                insertParams.addValue("ciXing", meaning.get("cixing") != null ? meaning.get("cixing") : "");
                insertParams.addValue("meaning", meaning.get("meaning") != null ? meaning.get("meaning") : "");
                insertParams.addValue("popularity", i + 1);
                insertParams.addValue("popularityPercent", null);
                insertParams.addValue("createTime", now);
                insertParams.addValue("updateTime", now);
                namedParameterJdbcTemplate.update(insertSql, insertParams);
            }
        }
    }

    public void createMeaningItem(MeaningItemDto dto) {
        String insertSql = "INSERT INTO meaning_item (id, word_id, dict_id, owner_id, ci_xing, meaning, popularity, popularity_percent, create_time, update_time, is_updating) "
                +
                "VALUES (:id, :wordId, :dictId, :ownerId, :ciXing, :meaning, :popularity, :popularityPercent, :createTime, :updateTime, false)";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("id", dto.getId());
        params.addValue("wordId", dto.getWordId());
        params.addValue("dictId", dto.getDictId());
        params.addValue("ownerId", dto.getOwnerId() != null ? dto.getOwnerId() : "15118");
        params.addValue("ciXing", dto.getCiXing() != null ? dto.getCiXing() : "");
        params.addValue("meaning", dto.getMeaning() != null ? dto.getMeaning() : "");
        params.addValue("popularity", dto.getPopularity());
        params.addValue("popularityPercent", dto.getPopularityPercent());
        params.addValue("createTime", dto.getCreateTime() != null ? new Timestamp(dto.getCreateTime().getTime()) : new Timestamp(System.currentTimeMillis()));
        params.addValue("updateTime", dto.getUpdateTime() != null ? new Timestamp(dto.getUpdateTime().getTime()) : new Timestamp(System.currentTimeMillis()));
        namedParameterJdbcTemplate.update(insertSql, params);
    }

    public void deleteMeaningItem(String id) {
        String deleteSql = "DELETE FROM meaning_item WHERE id = :id";
        MapSqlParameterSource params = new MapSqlParameterSource("id", id);
        namedParameterJdbcTemplate.update(deleteSql, params);
    }

    public MeaningItemDto toDto(MeaningItem meaningItem) {
        MeaningItemDto dto = new MeaningItemDto();
        dto.setId(meaningItem.getId());
        dto.setCiXing(meaningItem.getCiXing());
        dto.setMeaning(meaningItem.getMeaning());
        dto.setPopularity(meaningItem.getPopularity() != null ? meaningItem.getPopularity() : 999);
        dto.setPopularityPercent(meaningItem.getPopularityPercent());
        dto.setWordId(meaningItem.getWord() != null ? meaningItem.getWord().getId() : null);
        dto.setDictId(meaningItem.getDict() != null ? meaningItem.getDict().getId() : null);
        dto.setOwnerId(meaningItem.getOwner() != null ? meaningItem.getOwner().getId() : null);
        dto.setCreateTime(meaningItem.getCreateTime());
        dto.setUpdateTime(meaningItem.getUpdateTime());
        dto.setUpdating(meaningItem.getIsUpdating() != null ? meaningItem.getIsUpdating() : false);
        dto.setUpdatingStartAt(meaningItem.getUpdatingStartAt());
        return dto;
    }
}
