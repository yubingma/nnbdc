package beidanci.service.bo;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.stream.Collectors;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.MeaningItemDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.MeaningItem;

@Service
@Transactional(rollbackFor = Throwable.class)
public class MeaningItemBo extends BaseBo<MeaningItem> {
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<MeaningItem>() {
        });
    }

    /** 获取指定词书的所有单词释义项，通用词典ID为'0' */
    public List<MeaningItemDto> getMeaningItemsOfDict(String dictId) {
        // 通用词典现在是数据库中的实际记录，统一查询
        String sql = "SELECT id, ci_xing, meaning, word_id, dict_id, popularity, create_time, update_time FROM meaning_item WHERE dict_id = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        
        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            MeaningItemDto meaningItemDto = new MeaningItemDto();
            meaningItemDto.setId(rs.getString("id"));
            meaningItemDto.setCiXing(rs.getString("ci_xing"));
            meaningItemDto.setMeaning(rs.getString("meaning"));
            meaningItemDto.setWordId(rs.getString("word_id"));
            meaningItemDto.setDictId(rs.getString("dict_id"));
            // 处理 popularity 可能为 NULL 的情况，默认值为 999
            Integer popularity = rs.getObject("popularity", Integer.class);
            meaningItemDto.setPopularity(popularity != null ? popularity : 999);
            meaningItemDto.setCreateTime(rs.getTimestamp("create_time"));
            meaningItemDto.setUpdateTime(rs.getTimestamp("update_time"));
            return meaningItemDto;
        });
    }

    /**
     * 为给定的 wordId 集合，从任意词典中各取一条释义作为兜底（仅当该词在通用词典中无释义时使用）。
     */
    public List<MeaningItemDto> getOneMeaningPerWordFromAnyDict(List<String> wordIds) {
        if (wordIds == null || wordIds.isEmpty()) {
            return new ArrayList<>();
        }

        // 使用原生SQL一次性取回所有候选，再在内存中按 word 聚合取第一条
        String sql = "SELECT id, ci_xing, meaning, word_id, dict_id, popularity, create_time, update_time FROM meaning_item " +
                     "WHERE dict_id IS NOT NULL AND word_id IN (:ids) ORDER BY update_time DESC";
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
            dto.setCreateTime(rs.getTimestamp("create_time"));
            dto.setUpdateTime(rs.getTimestamp("update_time"));
            return dto;
        });
        
        // 转换为 Object[] 格式以保持原有逻辑
        List<?> results = allResults.stream().map(dto -> new Object[]{
            dto.getId(), dto.getCiXing(), dto.getMeaning(), dto.getWordId(), 
            dto.getDictId(), dto.getPopularity(), dto.getCreateTime(), dto.getUpdateTime()
        }).collect(Collectors.toList());

        List<MeaningItemDto> picked = new ArrayList<>();
        HashSet<String> seen = new HashSet<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            String wordId = (String) tuple[3];
            if (seen.contains(wordId)) {
                continue;
            }
            MeaningItemDto dto = new MeaningItemDto();
            dto.setId((String) tuple[0]);
            dto.setCiXing((String) tuple[1]);
            dto.setMeaning((String) tuple[2]);
            dto.setWordId(wordId);
            dto.setDictId((String) tuple[4]);
            // 处理 popularity 可能为 NULL 的情况，默认值为 999
            dto.setPopularity(tuple[5] != null ? (Integer) tuple[5] : 999);
            dto.setCreateTime((Timestamp) tuple[6]);
            dto.setUpdateTime((Timestamp) tuple[7]);
            picked.add(dto);
            seen.add(wordId);
            if (seen.size() == wordIds.size()) {
                break;
            }
        }
        return picked;
    }

    /**
     * 在数据库中为缺失通用释义（dictId = '0'）的单词，补充一条通用释义。
     * 逻辑：从任意词典的释义中拷贝一条，写入为通用释义（dictId='0'）。
     * 仅补充缺失项（NOT EXISTS 保证幂等）。
     * 返回插入的行数。
     */
    public int supplementCommonMeanings() {
        String sql =
                "INSERT INTO meaning_item (id, ci_xing, meaning, word_id, dict_id, popularity, create_time, update_time) " +
                "SELECT REPLACE(UUID(),'-',''), mi.ci_xing, mi.meaning, mi.word_id, '0', mi.popularity, NOW(6), NOW(6) " +
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
}
