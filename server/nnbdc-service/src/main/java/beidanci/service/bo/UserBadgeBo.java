package beidanci.service.bo;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javax.annotation.PostConstruct;

import org.apache.commons.lang3.tuple.Pair;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.UserBadgeDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.UserBadge;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserBadgeBo extends BaseBo<UserBadge> {

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<UserBadge>() {});
    }

    public UserBadgeDto toDto(UserBadge entity) {
        if (entity == null) {
            return null;
        }
        UserBadgeDto dto = new UserBadgeDto();
        dto.setId(entity.getId());
        dto.setUserId(entity.getUserId());
        dto.setBadgeCode(entity.getBadgeCode());
        dto.setObtainCount(entity.getObtainCount());
        dto.setStarLevel(entity.getStarLevel());
        dto.setUnlockedAt(entity.getUnlockedAt());
        dto.setIsEquipped(entity.getIsEquipped());
        dto.setIsViewed(entity.getIsViewed());
        dto.setCreateTime(entity.getCreateTime());
        dto.setUpdateTime(entity.getUpdateTime());
        return dto;
    }

    public UserBadge fromDto(UserBadgeDto dto) {
        if (dto == null) {
            return null;
        }
        UserBadge entity = null;
        if (dto.getId() != null) {
            entity = findById(dto.getId());
        }
        if (entity == null && dto.getUserId() != null && dto.getBadgeCode() != null) {
            entity = findByUserAndBadgeCode(dto.getUserId(), dto.getBadgeCode());
        }
        if (entity == null) {
            entity = new UserBadge();
            entity.setId(dto.getId());
            entity.setUserId(dto.getUserId());
            entity.setBadgeCode(dto.getBadgeCode());
        }
        entity.setObtainCount(dto.getObtainCount() != null ? dto.getObtainCount() : 1);
        entity.setStarLevel(dto.getStarLevel() != null ? dto.getStarLevel() : 1);
        entity.setUnlockedAt(dto.getUnlockedAt());
        entity.setIsEquipped(dto.getIsEquipped() != null ? dto.getIsEquipped() : false);
        entity.setIsViewed(dto.getIsViewed() != null ? dto.getIsViewed() : false);
        if (dto.getCreateTime() != null) {
            entity.setCreateTime(dto.getCreateTime());
        }
        if (dto.getUpdateTime() != null) {
            entity.setUpdateTime(dto.getUpdateTime());
        }
        return entity;
    }

    public List<UserBadgeDto> getUserBadgeDtosOfUser(String userId) {
        List<UserBadge> list = findByUserId(userId);
        List<UserBadgeDto> dtos = new ArrayList<>();
        for (UserBadge ub : list) {
            dtos.add(toDto(ub));
        }
        return dtos;
    }

    public List<UserBadge> findByUserId(String userId) {
        if (userId == null) {
            return Collections.emptyList();
        }
        String sql = "SELECT * FROM user_badge WHERE user_id = :userId";
        return pagedQuery(sql, 1, 1000, Pair.of("userId", userId)).getRows();
    }

    public UserBadge findByUserAndBadgeCode(String userId, String badgeCode) {
        if (userId == null || badgeCode == null) {
            return null;
        }
        String sql = "SELECT * FROM user_badge WHERE user_id = :userId AND badge_code = :badgeCode";
        return queryUnique(sql, Pair.of("userId", userId), Pair.of("badgeCode", badgeCode));
    }

    public void batchDeleteUserRecords(String userId, String filtersJson) {
        StringBuilder sql = new StringBuilder("DELETE FROM user_badge WHERE user_id = :userId");
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("userId", userId);
        namedParameterJdbcTemplate.update(sql.toString(), parameters);
    }
}
