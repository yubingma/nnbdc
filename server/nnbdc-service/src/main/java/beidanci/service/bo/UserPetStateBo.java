package beidanci.service.bo;

import java.util.Objects;

import javax.annotation.PostConstruct;
import org.springframework.transaction.annotation.Transactional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import beidanci.service.dao.BaseDao;
import beidanci.api.model.UserPetStateDto;
import beidanci.service.po.UserPetState;
import org.apache.commons.lang3.tuple.Pair;

/**
 * 记忆守护兽养成状态的业务对象。
 */
@Service
@Transactional(rollbackFor = Throwable.class)
public class UserPetStateBo extends BaseBo<UserPetState> {
    private static final Logger logger = LoggerFactory.getLogger(UserPetStateBo.class);

    @PostConstruct
    public void init() {
        setDao(new BaseDao<UserPetState>() {
        });
    }

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    /**
     * 按用户查询养成状态；每个用户至多一行。
     */
    public UserPetState findByUserId(String userId) {
        if (userId == null) {
            return null;
        }
        return queryUnique("SELECT * FROM user_pet_state WHERE user_id = :userId", Pair.of("userId", userId));
    }

    /**
     * 把用户的养成状态转成 DTO，供全量同步下发；没有记录时返回 null（不下发空行）。
     */
    public UserPetStateDto toDtoOfUser(String userId) {
        UserPetState state = findByUserId(userId);
        if (state == null) {
            return null;
        }
        UserPetStateDto dto = new UserPetStateDto();
        dto.setId(state.getId());
        dto.setUserId(userId);
        dto.setStageIndex(state.getStageIndex());
        dto.setTotalFeedings(state.getTotalFeedings());
        dto.setForm(state.getForm());
        dto.setCreateTime(state.getCreateTime());
        dto.setUpdateTime(state.getUpdateTime());
        return dto;
    }

    /**
     * 批量删除用户的养成状态（客户端清空数据时使用）。
     */
    public void batchDeleteUserRecords(String userId, String filtersJson) {
        String sql = "DELETE FROM user_pet_state WHERE user_id = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        int deleted = namedParameterJdbcTemplate.update(Objects.requireNonNull(sql, "SQL cannot be null"), params);
        logger.info("批量删除 user_pet_state 记录完成，用户 {}，删除数量 {}", userId, deleted);
    }
}
