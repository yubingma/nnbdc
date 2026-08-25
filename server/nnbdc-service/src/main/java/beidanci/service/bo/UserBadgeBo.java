package beidanci.service.bo;

import java.util.Collections;
import java.util.List;
import javax.annotation.PostConstruct;

import org.apache.commons.lang3.tuple.Pair;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.UserBadgeDao;
import beidanci.service.po.UserBadge;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserBadgeBo extends BaseBo<UserBadge> {

    @Autowired
    private UserBadgeDao userBadgeDao;

    @PostConstruct
    public void init() {
        setDao(userBadgeDao);
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
}
