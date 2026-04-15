package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.DakaDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.Daka;
import beidanci.service.po.DakaId;
import beidanci.service.po.StudyGroup;
import beidanci.service.po.User;

@Service
@Transactional(rollbackFor = Throwable.class)
public class DakaBo extends BaseBo<Daka> {
    @Autowired
    UserBo userBo;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<Daka>() {
        });
    }

    /**
     * 获取小组今日打卡人数
     *
     * @return
     */
    public int getTodaysDakaCount(StudyGroup studyGroup) {
        int count = 0;
        for (User user : studyGroup.getUsers()) {
            if (userBo.getHasDakaToday(user.getId())) {
                count++;
            }
        }
        return count;
    }

    public List<Daka> getDakaRecords(User user, Date startDate, Date endDate) {
        String sql = "SELECT * FROM daka WHERE user_id = :userId AND for_learning_date >= :startDate AND for_learning_date <= :endDate";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("userId", user.getId());
        params.addValue("startDate", startDate);
        params.addValue("endDate", endDate);
        return namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(Daka.class));
    }

    /**
     * 将实体对象转换为DTO
     *
     * @param entity 实体对象
     * @return DTO对象
     */
    public DakaDto toDto(Daka entity) {
        if (entity == null) {
            return null;
        }

        DakaDto dto = new DakaDto();
        dto.setUserId(entity.getUser().getId());
        dto.setForLearningDate(entity.getId().getForLearningDate());
        dto.setText(entity.getText());
        dto.setCreateTime(entity.getCreateTime());
        dto.setUpdateTime(entity.getUpdateTime());

        return dto;
    }

    /**
     * 获取用户的所有打卡记录DTO
     *
     * @param userId 用户ID
     * @return 打卡记录DTO列表
     */
    public List<DakaDto> getDakaDtosOfUser(String userId) {
        String sql = "SELECT * FROM daka WHERE user_id = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        List<Daka> dakas = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(Daka.class));

        List<DakaDto> dtos = new ArrayList<>();
        for (Daka daka : dakas) {
            dtos.add(toDto(daka));
        }

        return dtos;
    }

    /**
     * 根据DTO创建或更新实体
     *
     * @param dto DTO对象
     * @return 实体对象
     */
    public Daka fromDto(DakaDto dto) {
        User user = new User(dto.getUserId());
        DakaId id = new DakaId(dto.getUserId(), dto.getForLearningDate());

        Daka daka = findById(id);
        if (daka == null) {
            daka = new Daka(id, user, dto.getText());
        } else {
            daka.setText(dto.getText());
        }

        if (dto.getCreateTime() != null) {
            daka.setCreateTime(dto.getCreateTime());
        }
        if (dto.getUpdateTime() != null) {
            daka.setUpdateTime(dto.getUpdateTime());
        }

        return daka;
    }

    /**
     * 批量删除用户的dakas记录
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
            StringBuilder sql = new StringBuilder("DELETE FROM daka WHERE user_id = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("forLearningDate")) {
                sql.append(" AND for_learning_date = :forLearningDate");
                parameters.put("forLearningDate", filters.get("forLearningDate"));
            }
            if (filters.containsKey("textContent")) {
                sql.append(" AND textContent = :textContent");
                parameters.put("textContent", filters.get("textContent"));
            }
            
            MapSqlParameterSource params = new MapSqlParameterSource();
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                params.addValue(Objects.requireNonNull(entry.getKey(), "Parameter key cannot be null"), entry.getValue());
            }
            
            int deletedCount = namedParameterJdbcTemplate.update(Objects.requireNonNull(sql.toString(), "SQL cannot be null"), params);
            System.out.println("批量删除dakas记录完成，删除数量: " + deletedCount);
            
        } catch (DataAccessException e) {
            System.err.println("批量删除dakas记录失败，错误: " + e.getMessage());
            throw new RuntimeException("批量删除dakas记录失败: " + e.getMessage(), e);
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
