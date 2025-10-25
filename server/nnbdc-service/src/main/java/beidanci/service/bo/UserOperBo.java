package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.UserOperDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.UserOper;
import beidanci.service.util.Util;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserOperBo extends BaseBo<UserOper> {

        @PostConstruct
    public void init() {
        setDao(new BaseDao<UserOper>() {
        });
    }

    /**
     * 将实体对象转换为DTO对象
     *
     * @param entity 实体对象
     * @return DTO对象
     */
    public UserOperDto toDto(UserOper entity) {
        if (entity == null) {
            return null;
        }
        return new UserOperDto(
            entity.getId(),
            entity.getUserId(),
            entity.getOperType(),
            entity.getOperTime(),
            entity.getRemark(),
            entity.getCreateTime(),
            entity.getUpdateTime()
        );
    }

    /**
     * 将DTO对象转换为实体对象
     *
     * @param dto DTO对象
     * @return 实体对象
     */
    public UserOper fromDto(UserOperDto dto) {
        if (dto == null) {
            return null;
        }
        UserOper entity = new UserOper(
            dto.getId(),
            dto.getUserId(),
            dto.getOperType(),
            dto.getOperTime(),
            dto.getRemark()
        );
        entity.setCreateTime(dto.getCreateTime());
        entity.setUpdateTime(dto.getUpdateTime());
        return entity;
    }

    /**
     * 获取用户的所有操作历史记录DTO
     *
     * @param userId 用户ID
     * @return 操作历史记录DTO列表
     */
    public List<UserOperDto> getUserOperDtosOfUser(String userId) {
        String hql = "from UserOper where userId = :userId order by operTime desc";
        Query<UserOper> query = getSession().createQuery(hql, UserOper.class);
        query.setParameter("userId", userId);
        List<UserOper> opers = query.list();

        List<UserOperDto> result = new ArrayList<>();
        for (UserOper oper : opers) {
            result.add(toDto(oper));
        }
        return result;
    }

    /**
     * 记录用户登录操作
     *
     * @param userId 用户ID
     * @param remark 备注
     */
    public void recordLogin(String userId, String remark) {
        UserOper entity = new UserOper();
        entity.setId(Util.uuid());
        entity.setUserId(userId);
        entity.setOperType("LOGIN");
        entity.setOperTime(new Date());
        entity.setRemark(remark);
        entity.setCreateTime(new Date());
        entity.setUpdateTime(new Date());
        createEntity(entity);
    }

    /**
     * 记录用户开始学习操作
     *
     * @param userId 用户ID
     * @param remark 备注
     */
    public void recordStartLearn(String userId, String remark) {
        UserOper entity = new UserOper();
        entity.setId(Util.uuid());
        entity.setUserId(userId);
        entity.setOperType("START_LEARN");
        entity.setOperTime(new Date());
        entity.setRemark(remark);
        entity.setCreateTime(new Date());
        entity.setUpdateTime(new Date());
        createEntity(entity);
    }

    /**
     * 记录用户打卡操作
     *
     * @param userId 用户ID
     * @param remark 备注
     */
    public void recordDaka(String userId, String remark) {
        UserOper entity = new UserOper();
        entity.setId(Util.uuid());
        entity.setUserId(userId);
        entity.setOperType("DAKA");
        entity.setOperTime(new Date());
        entity.setRemark(remark);
        entity.setCreateTime(new Date());
        entity.setUpdateTime(new Date());
        createEntity(entity);
    }

    /**
     * 批量删除用户的user_oper记录
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
            StringBuilder sql = new StringBuilder("DELETE FROM user_oper WHERE userId = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("operType")) {
                sql.append(" AND operType = :operType");
                parameters.put("operType", filters.get("operType"));
            }
            if (filters.containsKey("operTime")) {
                sql.append(" AND operTime = :operTime");
                parameters.put("operTime", filters.get("operTime"));
            }
            if (filters.containsKey("remark")) {
                sql.append(" AND remark = :remark");
                parameters.put("remark", filters.get("remark"));
            }
            
            Query<?> query = getSession().createNativeQuery(sql.toString());
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                query.setParameter(entry.getKey(), entry.getValue());
            }
            
            int deletedCount = query.executeUpdate();
            System.out.println("批量删除user_oper记录完成，用户ID: " + userId + ", 删除数量: " + deletedCount);
            
        } catch (Exception e) {
            System.err.println("批量删除user_oper记录失败，用户ID: " + userId + ", 错误: " + e.getMessage());
            throw new RuntimeException("批量删除user_oper记录失败: " + e.getMessage(), e);
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
