package beidanci.service.bo;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

import javax.annotation.PostConstruct;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.StudyStep;
import beidanci.api.model.StudyStepState;
import beidanci.api.model.UserStudyStepDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.UserStudyStep;
import beidanci.service.po.UserStudyStepId;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserStudyStepBo extends BaseBo<UserStudyStep> {
    private static final Logger logger = LoggerFactory.getLogger(UserStudyStepBo.class);

    /** 学习规则的三个组名（group 是 SQL 保留字，DB 列名用 group_name） */
    private static final String GROUP_CHECK = "check";
    private static final String GROUP_CORRECT = "correct";
    private static final String GROUP_WRONG = "wrong";

    @PostConstruct
    public void init() {
        setDao(new BaseDao<UserStudyStep>() {
        });
    }

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    /**
     * 如果用户的学习步骤不足，则添加缺失的默认三组（scope='new' 新词 + scope='review' 旧词）。
     * 仅补缺，不覆盖用户已有配置：某组已有环节时保持原样。
     */
    public void initUserStudySteps(String userId) {
        // 新词默认三组: check=En2Ch、correct=[Ch2En]、wrong=[Ch2En]
        initScope(userId, "new", StudyStep.En2Ch,
                new StudyStep[] { StudyStep.Ch2En },
                new StudyStep[] { StudyStep.Ch2En });
        // 旧词默认三组: check=En2Ch、correct=[]、wrong=[Ch2En]
        initScope(userId, "review", StudyStep.En2Ch,
                new StudyStep[] {},
                new StudyStep[] { StudyStep.Ch2En });
    }

    /**
     * 为指定 scope 补缺三组：某组一条环节都没有时才插入默认环节（组内顺序从 0 开始）
     */
    private void initScope(String userId, String scope, StudyStep defaultCheck,
            StudyStep[] defaultCorrect, StudyStep[] defaultWrong) {
        List<UserStudyStep> steps = getStepsOfScope(userId, scope);
        boolean hasCheck = steps.stream().anyMatch(s -> GROUP_CHECK.equals(s.getId().getGroupName()));
        boolean hasCorrect = steps.stream().anyMatch(s -> GROUP_CORRECT.equals(s.getId().getGroupName()));
        boolean hasWrong = steps.stream().anyMatch(s -> GROUP_WRONG.equals(s.getId().getGroupName()));

        if (!hasCheck) {
            insertStep(userId, scope, GROUP_CHECK, defaultCheck, 0);
        }
        if (!hasCorrect) {
            for (int i = 0; i < defaultCorrect.length; i++) {
                insertStep(userId, scope, GROUP_CORRECT, defaultCorrect[i], i);
            }
        }
        if (!hasWrong) {
            for (int i = 0; i < defaultWrong.length; i++) {
                insertStep(userId, scope, GROUP_WRONG, defaultWrong[i], i);
            }
        }
    }

    private void insertStep(String userId, String scope, String group, StudyStep studyStep, int seq) {
        UserStudyStepId id = new UserStudyStepId(userId, scope, group, studyStep);
        UserStudyStep newStep = new UserStudyStep(id);
        newStep.setSeq(seq);
        newStep.setState(StudyStepState.Active);
        createEntity(newStep);
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
        String sql = "DELETE FROM user_study_step WHERE user_id = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        namedParameterJdbcTemplate.update(sql, params);
    }

    /**
     * 获取用户指定 scope 的所有学习步骤，按组+顺序排列
     */
    public List<UserStudyStep> getStepsOfScope(String userId, String scope) {
        String sql = "SELECT * FROM user_study_step WHERE user_id = :userId AND scope = :scope "
                + "ORDER BY group_name ASC, seq ASC";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("userId", userId);
        params.addValue("scope", scope);
        return namedParameterJdbcTemplate.query(sql, params, new EntityRowMapper<>(UserStudyStep.class));
    }

    /**
     * 获取用户的所有学习步骤（两个 scope 的全部三组），按 scope+组+顺序排列
     *
     * @param userId
     * @return
     */
    public List<UserStudyStep> getUserStudySteps(String userId) {
        // 重要：不要使用 BaseDao 的动态条件查询来过滤 user 字段。
        // BaseDao.pagedQuery 明确不支持用关联对象字段（Po 子类）作为查询条件，并且该异常会被吞掉，
        // 从而导致 userId 条件被静默忽略，误返回全表数据。
        String sql = "SELECT * FROM user_study_step WHERE user_id = :userId ORDER BY scope ASC, group_name ASC, seq ASC";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        return namedParameterJdbcTemplate.query(sql, params, new EntityRowMapper<>(UserStudyStep.class));
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
        dto.setScope(entity.getScope());
        dto.setGroup(entity.getGroupName());
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
     * 
     * @param userId      用户ID
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
            StringBuilder sql = new StringBuilder("DELETE FROM user_study_step WHERE user_id = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);

            // 添加过滤条件
            if (filters.containsKey("scope")) {
                sql.append(" AND scope = :scope");
                parameters.put("scope", filters.get("scope"));
            }
            if (filters.containsKey("group")) {
                sql.append(" AND group_name = :group");
                parameters.put("group", filters.get("group"));
            }
            if (filters.containsKey("studyStep")) {
                sql.append(" AND study_step = :studyStep");
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

            MapSqlParameterSource params = new MapSqlParameterSource();
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                params.addValue(Objects.requireNonNull(entry.getKey(), "Parameter key cannot be null"),
                        entry.getValue());
            }

            int deletedCount = namedParameterJdbcTemplate
                    .update(Objects.requireNonNull(sql.toString(), "SQL cannot be null"), params);
            System.out.println("批量删除user_study_step记录完成，删除数量: " + deletedCount);

        } catch (DataAccessException e) {
            logger.error("批量删除user_study_step记录失败", e);
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
