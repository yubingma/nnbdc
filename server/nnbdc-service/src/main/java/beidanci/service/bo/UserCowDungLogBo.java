package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.UserCowDungLogDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.UserCowDungLog;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserCowDungLogBo extends BaseBo<UserCowDungLog> {
    private static final Logger logger = LoggerFactory.getLogger(UserCowDungLogBo.class);
        @PostConstruct
    public void init() {
        setDao(new BaseDao<UserCowDungLog>() {
        });
    }

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    /**
     * 获取用户所有魔法泡泡日志的DTO列表，用于全量同步
     */
    public List<UserCowDungLogDto> getUserCowDungLogDtosOfUser(String userId) {
        String sql = "SELECT id, user_id, delta, cow_dung, the_time, reason, create_time, update_time FROM user_cow_dung_log WHERE user_id = :userId ORDER BY create_time";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        
        List<UserCowDungLogDto> userCowDungLogDtos = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            UserCowDungLogDto userCowDungLogDto = new UserCowDungLogDto();
            userCowDungLogDto.setId(rs.getString("id"));
            userCowDungLogDto.setUserId(rs.getString("user_id"));
            userCowDungLogDto.setDelta(rs.getInt("delta"));
            userCowDungLogDto.setCowDung(rs.getInt("cow_dung"));
            userCowDungLogDto.setTheTime(rs.getTimestamp("the_time"));
            userCowDungLogDto.setReason(rs.getString("reason"));
            userCowDungLogDto.setCreateTime(rs.getTimestamp("create_time"));
            userCowDungLogDto.setUpdateTime(rs.getTimestamp("update_time"));
            return userCowDungLogDto;
        });
        return userCowDungLogDtos;
    }

    /**
     * 批量删除用户的user_cow_dung_log记录
     * @param userId 用户ID
     * @param filtersJson 过滤条件JSON字符串
     */
    public void batchDeleteUserRecords(String userId, String filtersJson) {
        try {
            // 解析过滤条件
            Map<String, Object> filters = new HashMap<>();
            if (filtersJson != null && !filtersJson.trim().isEmpty()) {
                filters = parseFilters(filtersJson);
            }
            
            // 构建删除SQL
            StringBuilder sql = new StringBuilder("DELETE FROM user_cow_dung_log WHERE user_id = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("delta")) {
                sql.append(" AND delta = :delta");
                parameters.put("delta", filters.get("delta"));
            }
            if (filters.containsKey("cowDung")) {
                sql.append(" AND cow_dung = :cowDung");
                parameters.put("cowDung", filters.get("cowDung"));
            }
            if (filters.containsKey("theTime")) {
                sql.append(" AND the_time = :theTime");
                parameters.put("theTime", filters.get("theTime"));
            }
            if (filters.containsKey("reason")) {
                sql.append(" AND reason = :reason");
                parameters.put("reason", filters.get("reason"));
            }
            
            MapSqlParameterSource params = new MapSqlParameterSource();
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                params.addValue(Objects.requireNonNull(entry.getKey(), "Parameter key cannot be null"), entry.getValue());
            }
            
            int deletedCount = namedParameterJdbcTemplate.update(Objects.requireNonNull(sql.toString(), "SQL cannot be null"), params);
            System.out.println("批量删除user_cow_dung_log记录完成，用户ID: " + userId + ", 删除数量: " + deletedCount);
            
        } catch (DataAccessException e) {
            logger.error("批量删除user_cow_dung_log记录失败: userId={}", userId, e);
            throw new RuntimeException("批量删除user_cow_dung_log记录失败: " + e.getMessage(), e);
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
            System.err.println("解析过滤条件失败: " + e.getMessage());
        }
        return filters;
    }
}
