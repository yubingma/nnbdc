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

import beidanci.api.model.UserCowDungLogDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.UserCowDungLog;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserCowDungLogBo extends BaseBo<UserCowDungLog> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<UserCowDungLog>() {
        });
    }

    /**
     * 获取用户所有魔法泡泡日志的DTO列表，用于全量同步
     */
    public List<UserCowDungLogDto> getUserCowDungLogDtosOfUser(String userId) {
        String sql = "select id, userId, delta, cowDung, theTime, reason, createTime, updateTime from user_cow_dung_log where userId = :userId order by createTime";
        Query<?> query = getSession().createNativeQuery(sql);
        query.setParameter("userId", userId);
        List<?> results = query.list();

        List<UserCowDungLogDto> userCowDungLogDtos = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            UserCowDungLogDto userCowDungLogDto = new UserCowDungLogDto();
            userCowDungLogDto.setId((String) tuple[0]);
            userCowDungLogDto.setUserId((String) tuple[1]);
            userCowDungLogDto.setDelta((Integer) tuple[2]);
            userCowDungLogDto.setCowDung((Integer) tuple[3]);
            userCowDungLogDto.setTheTime((Date) tuple[4]);
            userCowDungLogDto.setReason((String) tuple[5]);
            userCowDungLogDto.setCreateTime((Date) tuple[6]);
            userCowDungLogDto.setUpdateTime((Date) tuple[7]);
            userCowDungLogDtos.add(userCowDungLogDto);
        }
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
            StringBuilder sql = new StringBuilder("DELETE FROM user_cow_dung_log WHERE userId = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("delta")) {
                sql.append(" AND delta = :delta");
                parameters.put("delta", filters.get("delta"));
            }
            if (filters.containsKey("cowDung")) {
                sql.append(" AND cowDung = :cowDung");
                parameters.put("cowDung", filters.get("cowDung"));
            }
            if (filters.containsKey("theTime")) {
                sql.append(" AND theTime = :theTime");
                parameters.put("theTime", filters.get("theTime"));
            }
            if (filters.containsKey("reason")) {
                sql.append(" AND reason = :reason");
                parameters.put("reason", filters.get("reason"));
            }
            
            Query<?> query = getSession().createNativeQuery(sql.toString());
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                query.setParameter(entry.getKey(), entry.getValue());
            }
            
            int deletedCount = query.executeUpdate();
            System.out.println("批量删除user_cow_dung_log记录完成，用户ID: " + userId + ", 删除数量: " + deletedCount);
            
        } catch (Exception e) {
            System.err.println("批量删除user_cow_dung_log记录失败，用户ID: " + userId + ", 错误: " + e.getMessage());
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
