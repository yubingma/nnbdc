package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.io.IOException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

import org.apache.commons.lang3.tuple.ImmutablePair;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.WordVo;
import beidanci.api.model.WrongWordDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.WrongWord;
import beidanci.service.store.WordCache;

@Service
@Transactional(rollbackFor = Throwable.class)
public class WrongWordBo extends BaseBo<WrongWord> {

        @PostConstruct
    public void init() {
        setDao(new BaseDao<WrongWord>() {
        });
    }

    @Autowired
    WordCache wordCache;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    public int getWrongWordOrder(String userId, String spell) throws InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        WordVo word = wordCache.getWordBySpell(spell, new String[]{
                "SynonymVo.meaningItem", "SynonymVo.word",  "similarWords", "DictVo.dictWords"});
        if (word == null) {
            return -1;
        }

        // 转换为 SQL（注意：复合主键需要特殊处理）
        String sql = "SELECT * FROM user_wrong_word WHERE user_id = :userId AND word_id = :wordId";
        WrongWord wrongWord = queryUnique(sql,
                new ImmutablePair<>("userId", userId),
                new ImmutablePair<>("wordId", word.getId()));
        if (wrongWord == null) {
            return -1;
        }

        // 转换为 SQL
        String countSql = "SELECT COUNT(*) FROM user_wrong_word WHERE user_id = :userId AND create_time <= :createTime";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("userId", userId);
        params.addValue("createTime", wrongWord.getCreateTime());
        Long count = namedParameterJdbcTemplate.queryForObject(countSql, params, Long.class);
        return count != null ? count.intValue() : 0;
    }

    /**
     * 幂等创建：若已存在则忽略
     * 
     * 使用 findById 而不是 queryUnique，避免在事务中因 Hibernate 会话缓存状态不一致导致的异常
     */
    public void createIfAbsent(WrongWord wrongWord) {
        WrongWord existing = findById(wrongWord.getId());
        if (existing == null) {
            createEntity(wrongWord);
        }
    }

    /**
     * 获取用户所有错词的DTO列表，用于全量同步
     */
    public List<WrongWordDto> getWrongWordDtosOfUser(String userId) {
        String sql = "SELECT user_id, word_id, create_time, update_time FROM user_wrong_word WHERE user_id = :userId ORDER BY create_time";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        
        List<WrongWordDto> dtos = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            WrongWordDto dto = new WrongWordDto();
            dto.setUserId(rs.getString("user_id"));
            dto.setWordId(rs.getString("word_id"));
            dto.setCreateTime(rs.getTimestamp("create_time"));
            dto.setUpdateTime(rs.getTimestamp("update_time"));
            return dto;
        });

        return dtos;
    }

    /**
     * 批量删除用户的user_wrong_word记录
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
            StringBuilder sql = new StringBuilder("DELETE FROM user_wrong_word WHERE user_id = :userId");
            MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("wordId")) {
                sql.append(" AND word_id = :wordId");
                params.addValue("wordId", filters.get("wordId"));
            }
            if (filters.containsKey("createTime")) {
                sql.append(" AND create_time = :createTime");
                params.addValue("createTime", filters.get("createTime"));
            }
            
            int deletedCount = namedParameterJdbcTemplate.update(Objects.requireNonNull(sql.toString(), "SQL cannot be null"), params);
            System.out.println("批量删除user_wrong_word记录完成，删除数量: " + deletedCount);
            
        } catch (DataAccessException e) {
            System.err.println("批量删除user_wrong_word记录失败，错误: " + e.getMessage());
            throw new RuntimeException("批量删除user_wrong_word记录失败: " + e.getMessage(), e);
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
