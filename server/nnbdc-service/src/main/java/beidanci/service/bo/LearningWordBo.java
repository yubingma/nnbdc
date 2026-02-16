package beidanci.service.bo;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import javax.annotation.PostConstruct;


import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.LearningWordDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.LearningWord;

@Service
@Transactional(rollbackFor = Throwable.class)
public class LearningWordBo extends BaseBo<LearningWord> {
    private static final Logger log = LoggerFactory.getLogger(LearningWordBo.class);

    @PostConstruct
    public void init() {
        setDao(new BaseDao<LearningWord>() {
        });
    }


    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    public boolean hasLearningWordsOfDict(String userId, String dictId) {
        String sql = "SELECT COUNT(*) FROM learning_word lw " +
                "INNER JOIN dict_word dw ON lw.word_id = dw.word_id " +
                "WHERE lw.user_id = :userId AND dw.dict_id = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("userId", userId);
        params.addValue("dictId", dictId);
        Long count = namedParameterJdbcTemplate.queryForObject(sql, params, Long.class);
        return count != null && count > 0;
    }

    public List<LearningWordDto> getLearningWordDtosOfUser(String userId) {
        String sql = "SELECT user_id, word_id, learning_order, is_today_new_word, life_value, last_learning_date, add_time, add_day, learned_times, batch_id, create_time, update_time FROM learning_word WHERE user_id = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        
        List<LearningWordDto> dtos = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            LearningWordDto dto = new LearningWordDto();
            dto.setUserId(rs.getString("user_id"));
            dto.setWordId(rs.getString("word_id"));
            dto.setLearningOrder(rs.getInt("learning_order"));
            dto.setIsTodayNewWord(rs.getBoolean("is_today_new_word"));
            dto.setLifeValue(rs.getInt("life_value"));
            dto.setLastLearningDate(rs.getTimestamp("last_learning_date"));
            dto.setAddTime(rs.getTimestamp("add_time"));
            dto.setAddDay(rs.getInt("add_day"));
            dto.setLearnedTimes(rs.getInt("learned_times"));
            dto.setBatchId(rs.getInt("batch_id"));
            dto.setCreateTime(rs.getTimestamp("create_time"));
            dto.setUpdateTime(rs.getTimestamp("update_time"));
            return dto;
        });

        return dtos;
    }

    /**
     * 批量删除用户的学习单词记录
     * @param userId 用户ID
     * @param filtersJson 过滤条件JSON字符串
     */
    public void batchDeleteUserRecords(String userId, String filtersJson) {
        try {
            // 解析过滤条件
            Map<String, Object> filters = new HashMap<>();
            if (filtersJson != null && !filtersJson.trim().isEmpty()) {
                // 简单的JSON解析，这里可以根据需要改进
                filters = parseFilters(filtersJson);
            }
            
            // 构建删除SQL
            StringBuilder sql = new StringBuilder("DELETE FROM learning_word WHERE user_id = :userId");
            MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("wordId")) {
                sql.append(" AND word_id = :wordId");
                params.addValue("wordId", filters.get("wordId"));
            }
            if (filters.containsKey("lifeValue")) {
                sql.append(" AND life_value = :lifeValue");
                params.addValue("lifeValue", filters.get("lifeValue"));
            }
            if (filters.containsKey("lastLearningDate")) {
                sql.append(" AND last_learning_date = :lastLearningDate");
                params.addValue("lastLearningDate", filters.get("lastLearningDate"));
            }
            
            int deletedCount = namedParameterJdbcTemplate.update(Objects.requireNonNull(sql.toString(), "SQL cannot be null"), params);
            log.info("批量删除学习单词记录完成，用户ID: {}, 删除数量: {}", userId, deletedCount);
            
        } catch (Exception e) {
            log.error("批量删除学习单词记录失败，用户ID: {}, 错误: {}", userId, e.getMessage(), e);
            throw new RuntimeException("批量删除学习单词记录失败: " + e.getMessage(), e);
        }
    }
    
    /**
     * 简单的JSON解析方法，将JSON字符串转换为Map
     */
    private Map<String, Object> parseFilters(String filtersJson) {
        Map<String, Object> filters = new HashMap<>();
        try {
            // 移除JSON的大括号
            String content = filtersJson.trim();
            if (content.startsWith("{") && content.endsWith("}")) {
                content = content.substring(1, content.length() - 1);
            }
            
            // 简单的键值对解析
            String[] pairs = content.split(",");
            for (String pair : pairs) {
                String[] keyValue = pair.split(":");
                if (keyValue.length == 2) {
                    String key = keyValue[0].trim().replace("\"", "");
                    String value = keyValue[1].trim().replace("\"", "");
                    filters.put(key, value);
                }
            }
        } catch (Exception e) {
            log.warn("解析过滤条件失败: {}", e.getMessage());
        }
        return filters;
    }

}
