package beidanci.service.bo;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import javax.annotation.PostConstruct;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.LearningLogDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.LearningLog;

@Service
@Transactional(rollbackFor = Throwable.class)
public class LearningLogBo extends BaseBo<LearningLog> {
    private static final Logger logger = LoggerFactory.getLogger(LearningLogBo.class);

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<LearningLog>() {});
    }

    public List<LearningLogDto> getLearningLogDtosOfUser(String userId) {
        String sql = "SELECT id, user_id, word_id, rating, stability, difficulty, elapsed_days, scheduled_days, create_time, update_time FROM learning_log WHERE user_id = :userId ORDER BY create_time";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);

        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            LearningLogDto dto = new LearningLogDto();
            dto.setId(rs.getString("id"));
            dto.setUserId(rs.getString("user_id"));
            dto.setWordId(rs.getString("word_id"));
            dto.setRating(rs.getInt("rating"));
            dto.setStability(rs.getDouble("stability"));
            dto.setDifficulty(rs.getDouble("difficulty"));
            dto.setElapsedDays(rs.getInt("elapsed_days"));
            dto.setScheduledDays(rs.getInt("scheduled_days"));
            dto.setCreateTime(rs.getTimestamp("create_time"));
            dto.setUpdateTime(rs.getTimestamp("update_time"));
            return dto;
        });
    }

    public void batchDeleteUserRecords(String userId, String filtersJson) {
        try {
            Map<String, Object> filters = new HashMap<>();
            if (filtersJson != null && !filtersJson.trim().isEmpty()) {
                filters = parseFilters(filtersJson);
            }

            StringBuilder sql = new StringBuilder("DELETE FROM learning_log WHERE user_id = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);

            if (filters.containsKey("wordId")) {
                sql.append(" AND word_id = :wordId");
                parameters.put("wordId", filters.get("wordId"));
            }

            MapSqlParameterSource params = new MapSqlParameterSource();
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                params.addValue(Objects.requireNonNull(entry.getKey(), "Parameter key cannot be null"), entry.getValue());
            }

            int deletedCount = namedParameterJdbcTemplate.update(Objects.requireNonNull(sql.toString(), "SQL cannot be null"), params);
            logger.info("批量删除learning_log记录完成，用户ID: {}, 删除数量: {}", userId, deletedCount);

        } catch (DataAccessException e) {
            logger.error("批量删除learning_log记录失败: userId={}", userId, e);
            throw new RuntimeException("批量删除learning_log记录失败: " + e.getMessage(), e);
        }
    }

    private Map<String, Object> parseFilters(String filtersJson) {
        Map<String, Object> filters = new HashMap<>();
        try {
            String content = filtersJson.trim();
            if (content.startsWith("{") && content.endsWith("}")) {
                content = content.substring(1, content.length() - 1);
            }
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
            logger.error("解析过滤条件失败: {}", e.getMessage());
        }
        return filters;
    }
}
