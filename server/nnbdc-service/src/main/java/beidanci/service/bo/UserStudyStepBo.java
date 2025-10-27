package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.hibernate.query.Query;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.ClientType;
import beidanci.api.model.StudyStep;
import beidanci.api.model.StudyStepState;
import beidanci.api.model.UserStudyStepDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.User;
import beidanci.service.po.UserStudyStep;
import beidanci.service.po.UserStudyStepId;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserStudyStepBo extends BaseBo<UserStudyStep> {

        @PostConstruct
    public void init() {
        setDao(new BaseDao<UserStudyStep>() {
        });
    }


    /**
     * 如果用户的学习步骤不足， 则添加缺失的学习步骤
     *
     * @param clientType
     * @param userId
     */
    public void initUserStudySteps(ClientType clientType, String userId) {
        // 如果用户的学习步骤不足， 则添加缺失的学习步骤
        List<UserStudyStep> userStudySteps = getUserStudySteps(userId);
        List<StudyStep> existingSteps = userStudySteps.stream().map(UserStudyStep::getStudyStep).collect(Collectors.toList());
        if (existingSteps.size() < StudyStep.values().length) {
            UserStudyStepId id;
            UserStudyStep step;

            List<UserStudyStep> newSteps = getUserStudySteps(userId);

            if (!existingSteps.contains(StudyStep.Word)) {
                id = new UserStudyStepId(userId, StudyStep.Word);
                step = new UserStudyStep(id);
                step.setSeq(1);
                step.setState(StudyStepState.Active);
                newSteps.add(step);
            }

            if (!existingSteps.contains(StudyStep.Meaning)) {
                id = new UserStudyStepId(userId, StudyStep.Meaning);
                step = new UserStudyStep(id);
                step.setSeq(2);
                step.setState(StudyStepState.Active);
                newSteps.add(step);
            }

            saveStudySteps(newSteps, userId, false);
        }
    }

    public void saveStudySteps(List<UserStudyStep> studySteps, String userId, boolean clearFirst) {
        // 清除当前的学习步骤
        if (clearFirst) {
            clearUserStudySteps(userId);
        }

        // 新增学习步骤
        for (UserStudyStep studyStep : studySteps) {
            createEntity(studyStep);
        }
    }

    /**
     * 清除用户的学习步骤
     */
    public void clearUserStudySteps(String userId) {
        String hql = "delete from UserStudyStep where user.id = :userId";
        getSession().createQuery(hql)
                .setParameter("userId", userId)
                .executeUpdate();
    }

    /**
     * 获取用户的所有学习步骤，按顺序排列
     *
     * @param userId
     * @return
     */
    public List<UserStudyStep> getUserStudySteps(String userId) {
        UserStudyStep exam = new UserStudyStep();
        exam.setUser(new User(userId));
        List<UserStudyStep> steps = queryAll(exam, "seq", "asc", false);
        return steps;
    }

    /**
     * 获取用户的所有处于激活状态的学习步骤，按顺序排列
     *
     * @param userId
     * @return
     */
    public List<UserStudyStep> getActiveStudyStepsOfUser(String userId) {
        UserStudyStep exam = new UserStudyStep();
        exam.setUser(new User(userId));
        exam.setState(StudyStepState.Active);
        List<UserStudyStep> activeSteps = queryAll(exam, "seq", "asc", false);
        return activeSteps;
    }

    /**
     * 删除指定的学习步骤
     *
     * @param studyStep 要删除的学习步骤
     */
    @Override
    public void deleteEntity(UserStudyStep studyStep) {
        super.deleteEntity(studyStep);
    }

    /**
     * 将实体对象转换为DTO
     *
     * @param entity 实体对象
     * @return DTO对象
     */
    public UserStudyStepDto toDto(UserStudyStep entity) {
        if (entity == null) {
            return null;
        }

        UserStudyStepDto dto = new UserStudyStepDto();
        dto.setUserId(entity.getUser().getId());
        dto.setStudyStep(entity.getStudyStep());
        dto.setSeq(entity.getSeq());
        dto.setState(entity.getState());
        dto.setCreateTime(entity.getCreateTime());
        dto.setUpdateTime(entity.getUpdateTime());

        return dto;
    }

    /**
     * 获取用户的所有学习步骤DTO
     *
     * @param userId 用户ID
     * @return 学习步骤DTO列表
     */
    public List<UserStudyStepDto> getUserStudyStepDtosOfUser(String userId) {
        List<UserStudyStep> steps = getUserStudySteps(userId);
        List<UserStudyStepDto> dtos = new ArrayList<>();

        for (UserStudyStep step : steps) {
            dtos.add(toDto(step));
        }

        return dtos;
    }

    /**
     * 批量删除用户的user_study_step记录
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
            StringBuilder sql = new StringBuilder("DELETE FROM user_study_step WHERE userId = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("studyStep")) {
                sql.append(" AND studyStep = :studyStep");
                parameters.put("studyStep", filters.get("studyStep"));
            }
            if (filters.containsKey("state")) {
                sql.append(" AND state = :state");
                parameters.put("state", filters.get("state"));
            }
            if (filters.containsKey("seq")) {
                sql.append(" AND seq = :seq");
                parameters.put("seq", filters.get("seq"));
            }
            
            Query<?> query = getSession().createNativeQuery(sql.toString());
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                query.setParameter(entry.getKey(), entry.getValue());
            }
            
            int deletedCount = query.executeUpdate();
            System.out.println("批量删除user_study_step记录完成，用户ID: " + userId + ", 删除数量: " + deletedCount);
            
        } catch (Exception e) {
            System.err.println("批量删除user_study_step记录失败，用户ID: " + userId + ", 错误: " + e.getMessage());
            throw new RuntimeException("批量删除user_study_step记录失败: " + e.getMessage(), e);
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
