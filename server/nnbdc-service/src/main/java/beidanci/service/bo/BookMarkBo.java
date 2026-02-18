package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.HashMap;
import java.util.Map;
import java.util.Objects;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.BookMark;
import beidanci.service.po.BookMarkId;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(rollbackFor = Throwable.class)
public class BookMarkBo extends BaseBo<BookMark> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<BookMark>() {
        });
    }

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    public void saveBookMark(String bookMarkName, String spell, int position, String userId) throws IllegalAccessException {
        BookMarkId id = new BookMarkId(userId, bookMarkName);
        BookMark existing = findById(id);
        if (existing != null) {
            existing.setPosition(position);
            existing.setSpell(spell);
            updateEntity(existing);
        } else {
            BookMark bookMark = new BookMark(id);
            bookMark.setPosition(position);
            bookMark.setSpell(spell);
            createEntity(bookMark);
        }
    }

    /**
     * 批量删除用户的book_mark记录
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
            StringBuilder sql = new StringBuilder("DELETE FROM book_mark WHERE user_id = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("bookMarkName")) {
                sql.append(" AND book_mark_name = :bookMarkName");
                parameters.put("bookMarkName", filters.get("bookMarkName"));
            }
            if (filters.containsKey("spell")) {
                sql.append(" AND spell = :spell");
                parameters.put("spell", filters.get("spell"));
            }
            if (filters.containsKey("createTime")) {
                sql.append(" AND create_time = :createTime");
                parameters.put("createTime", filters.get("createTime"));
            }
            
            MapSqlParameterSource params = new MapSqlParameterSource();
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                params.addValue(Objects.requireNonNull(entry.getKey(), "Parameter key cannot be null"), entry.getValue());
            }
            
            int deletedCount = namedParameterJdbcTemplate.update(Objects.requireNonNull(sql.toString(), "SQL cannot be null"), params);
            System.out.println("批量删除book_mark记录完成，用户ID: " + userId + ", 删除数量: " + deletedCount);
            
        } catch (DataAccessException e) {
            System.err.println("批量删除book_mark记录失败，用户ID: " + userId + ", 错误: " + e.getMessage());
            throw new RuntimeException("批量删除book_mark记录失败: " + e.getMessage(), e);
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
