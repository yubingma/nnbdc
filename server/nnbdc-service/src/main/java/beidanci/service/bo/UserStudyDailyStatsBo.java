package beidanci.service.bo;

import beidanci.api.model.UserStudyDailyStatsDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.UserStudyDailyStats;
import beidanci.service.po.UserStudyDailyStatsId;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.PostConstruct;
import java.util.*;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserStudyDailyStatsBo extends BaseBo<UserStudyDailyStats> {

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<UserStudyDailyStats>() {
        });
    }

    public UserStudyDailyStatsDto toDto(UserStudyDailyStats entity) {
        if (entity == null) {
            return null;
        }
        UserStudyDailyStatsDto dto = new UserStudyDailyStatsDto();
        dto.setUserId(entity.getId().getUserId());
        dto.setDate(entity.getId().getDate());
        dto.setStudySeconds(entity.getStudySeconds());
        dto.setReviewCount(entity.getReviewCount());
        dto.setDayStatus(entity.getDayStatus());
        return dto;
    }

    public List<UserStudyDailyStatsDto> getStatsDtosOfUser(String userId) {
        String sql = "SELECT * FROM user_study_daily_stats WHERE user_id = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        List<UserStudyDailyStats> stats = namedParameterJdbcTemplate.query(sql, params,
                new EntityRowMapper<>(UserStudyDailyStats.class));

        List<UserStudyDailyStatsDto> dtos = new ArrayList<>();
        for (UserStudyDailyStats stat : stats) {
            dtos.add(toDto(stat));
        }
        return dtos;
    }

    public UserStudyDailyStats fromDto(UserStudyDailyStatsDto dto) {
        UserStudyDailyStatsId id = new UserStudyDailyStatsId(dto.getUserId(), dto.getDate());
        UserStudyDailyStats entity = findById(id);
        if (entity == null) {
            entity = new UserStudyDailyStats(id, dto.getStudySeconds(), dto.getReviewCount(), dto.getDayStatus());
        } else {
            entity.setStudySeconds(dto.getStudySeconds());
            entity.setReviewCount(dto.getReviewCount());
            entity.setDayStatus(dto.getDayStatus());
        }
        return entity;
    }

    public void batchDeleteUserRecords(String userId, String filtersJson) {
        try {
            Map<String, Object> filters = new HashMap<>();
            if (filtersJson != null && !filtersJson.trim().isEmpty()) {
                filters = parseFilters(filtersJson);
            }

            StringBuilder sql = new StringBuilder("DELETE FROM user_study_daily_stats WHERE user_id = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);

            if (filters.containsKey("date")) {
                sql.append(" AND date = :date");
                parameters.put("date", filters.get("date"));
            }

            MapSqlParameterSource params = new MapSqlParameterSource();
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                params.addValue(Objects.requireNonNull(entry.getKey(), "Parameter key cannot be null"), entry.getValue());
            }

            namedParameterJdbcTemplate.update(Objects.requireNonNull(sql.toString(), "SQL cannot be null"), params);
        } catch (DataAccessException e) {
            throw new RuntimeException("批量删除 user_study_daily_stats 记录失败: " + e.getMessage(), e);
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
            // Log error
        }
        return filters;
    }
}
