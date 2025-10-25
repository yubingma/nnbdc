package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.hibernate.query.Query;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.DakaDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.Daka;
import beidanci.service.po.DakaId;
import beidanci.service.po.StudyGroup;
import beidanci.service.po.User;

@Service
@Transactional(rollbackFor = Throwable.class)
public class DakaBo extends BaseBo<Daka> {
    @Autowired
    UserBo userBo;

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
        String hql = "from Daka sr where user = :user and forLearningDate >= :startDate and forLearningDate <= :endDate";

        Query<Daka> query = getSession().createQuery(hql, Daka.class);
        query.setParameter("user", user);
        query.setParameter("startDate", startDate);
        query.setParameter("endDate", endDate);
        return query.list();
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
        String hql = "from Daka d where d.user.id = :userId";

        Query<Daka> query = getSession().createQuery(hql, Daka.class);
        query.setParameter("userId", userId);
        List<Daka> dakas = query.list();

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
            StringBuilder sql = new StringBuilder("DELETE FROM dakas WHERE userId = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("forLearningDate")) {
                sql.append(" AND forLearningDate = :forLearningDate");
                parameters.put("forLearningDate", filters.get("forLearningDate"));
            }
            if (filters.containsKey("textContent")) {
                sql.append(" AND textContent = :textContent");
                parameters.put("textContent", filters.get("textContent"));
            }
            
            Query<?> query = getSession().createNativeQuery(sql.toString());
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                query.setParameter(entry.getKey(), entry.getValue());
            }
            
            int deletedCount = query.executeUpdate();
            System.out.println("批量删除dakas记录完成，用户ID: " + userId + ", 删除数量: " + deletedCount);
            
        } catch (Exception e) {
            System.err.println("批量删除dakas记录失败，用户ID: " + userId + ", 错误: " + e.getMessage());
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
