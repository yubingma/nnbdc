package beidanci.service.bo;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.LearningDictDto;
import beidanci.api.model.WordVo;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.LearningDict;
import beidanci.service.po.User;

@Service
@Transactional(rollbackFor = Throwable.class)
public class LearningDictBo extends BaseBo<LearningDict> {
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<LearningDict>() {
        });
    }

    public List<LearningDict> getLearningDictsOfUser(User user) {
        String sql = "SELECT * FROM learning_dict WHERE user_id = :userId ORDER BY create_time ASC";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", user.getId());
        return namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(LearningDict.class));
    }

    public LearningDict getLearningDictOfUser(User user, String dictName) {
        String sql = "SELECT ld.* FROM learning_dict ld INNER JOIN dict d ON ld.dict_id = d.id WHERE ld.user_id = :userId AND d.name = :dictName";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("userId", user.getId());
        params.addValue("dictName", dictName);
        List<LearningDict> results = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(LearningDict.class));
        return results.isEmpty() ? null : results.get(0);
    }

    public boolean needSelectDictBeforeStudy(User user) {
        String sql = "SELECT COUNT(*) FROM dict_word dw " +
                "INNER JOIN learning_dict ld ON dw.dict_id = ld.dict_id " +
                "WHERE ld.user_id = :userId " +
                "AND NOT EXISTS (SELECT 0 FROM mastered_word mw WHERE mw.user_id = ld.user_id AND mw.word_id = dw.word_id) " +
                "AND NOT EXISTS (SELECT 0 FROM learning_word lw WHERE lw.user_id = ld.user_id AND lw.word_id = dw.word_id)";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", user.getId());
        Long count = namedParameterJdbcTemplate.queryForObject(sql, params, Long.class);
        return count == null || count == 0;
    }

    /**
     * 判断指定单词是否在用户选择的单词书中
     *
     * @param user
     * @return
     */
    public boolean isWordInMySelectedDicts(WordVo word, User user) {
        // 判断单词是否在用户选择的词书中
        String sql = "SELECT COUNT(*) FROM dict_word dw " +
                     "INNER JOIN learning_dict ld ON dw.dict_id = ld.dict_id " +
                     "WHERE dw.word_id = :wordId AND ld.user_id = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("wordId", word.getId());
        params.addValue("userId", user.getId());
        Long total = namedParameterJdbcTemplate.queryForObject(sql, params, Long.class);
        return total != null && total > 0;
    }

    public List<LearningDictDto> getLearningDictDtosOfUser(String userId) {
        String sql = "SELECT user_id, dict_id, is_privileged, fetch_mastered, create_time, update_time FROM learning_dict WHERE user_id = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        
        List<LearningDictDto> dtos = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            LearningDictDto dto = new LearningDictDto();
            dto.setUserId(rs.getString("user_id"));
            dto.setDictId(rs.getString("dict_id"));
            dto.setIsPrivileged(rs.getBoolean("is_privileged"));
            dto.setFetchMastered(rs.getBoolean("fetch_mastered"));
            dto.setCreateTime(rs.getTimestamp("create_time"));
            dto.setUpdateTime(rs.getTimestamp("update_time"));
            return dto;
        });
        return dtos;
    }

    /**
     * 批量删除用户的学习词典记录
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
            StringBuilder sql = new StringBuilder("DELETE FROM learning_dict WHERE user_id = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("dictId")) {
                sql.append(" AND dict_id = :dictId");
                parameters.put("dictId", filters.get("dictId"));
            }
            if (filters.containsKey("isPrivileged")) {
                sql.append(" AND is_privileged = :isPrivileged");
                parameters.put("isPrivileged", filters.get("isPrivileged"));
            }
            
            MapSqlParameterSource params = new MapSqlParameterSource();
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                params.addValue(Objects.requireNonNull(entry.getKey(), "Parameter key cannot be null"), entry.getValue());
            }
            
            int deletedCount = namedParameterJdbcTemplate.update(Objects.requireNonNull(sql.toString(), "SQL cannot be null"), params);
            System.out.println("批量删除学习词典记录完成，用户ID: " + userId + ", 删除数量: " + deletedCount);
            
        } catch (DataAccessException e) {
            System.err.println("批量删除学习词典记录失败，用户ID: " + userId + ", 错误: " + e.getMessage());
            throw new RuntimeException("批量删除学习词典记录失败: " + e.getMessage(), e);
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

    // ============================================
    // 系统健康检查相关方法
    // ============================================

    // current_word_seq 已移除，相关健康检查和修复逻辑不再需要
}
