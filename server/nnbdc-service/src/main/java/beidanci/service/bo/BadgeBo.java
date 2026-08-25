package beidanci.service.bo;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.Badge;
import beidanci.api.model.BadgeVo;
import beidanci.api.model.UserBadgeVo;
import beidanci.service.po.User;
import beidanci.service.po.UserBadge;

@Service
@Transactional(rollbackFor = Throwable.class)
public class BadgeBo {
    private static final Logger log = LoggerFactory.getLogger(BadgeBo.class);

    @Autowired
    private UserBadgeBo userBadgeBo;

    @Autowired
    private UserBo userBo;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    /**
     * 获取用户全量勋章展示列表（基于 Badge 枚举与用户达成记录装配）
     */
    public List<UserBadgeVo> getMyBadges(User user) {
        List<UserBadge> userBadges = (user != null) ? userBadgeBo.findByUserId(user.getId()) : Collections.emptyList();
        Map<String, UserBadge> userBadgeMap = new HashMap<>();
        for (UserBadge ub : userBadges) {
            userBadgeMap.put(ub.getBadgeCode(), ub);
        }

        int streakDays = (user != null && user.getContinuousDakaDayCount() != null) ? user.getContinuousDakaDayCount() : 0;
        int masteredWords = (user != null && user.getId() != null) ? getMasteredWordCountOfUser(user.getId()) : 0;

        List<UserBadgeVo> resultList = new ArrayList<>();
        for (Badge badge : Badge.values()) {
            UserBadgeVo vo = new UserBadgeVo();
            vo.setBadgeCode(badge.name());
            vo.setBadge(BadgeVo.fromBadge(badge));

            UserBadge ub = userBadgeMap.get(badge.name());
            if (ub != null) {
                vo.setId(ub.getId());
                vo.setUserId(ub.getUserId());
                vo.setIsUnlocked(true);
                vo.setObtainCount(ub.getObtainCount());
                vo.setStarLevel(ub.getStarLevel());
                vo.setUnlockedAt(ub.getUnlockedAt());
                vo.setIsEquipped(ub.getIsEquipped());
                vo.setIsViewed(ub.getIsViewed());
                vo.setProgressCurrent(badge.getTargetValue());
                vo.setProgressTarget(badge.getTargetValue());
                vo.setProgressPercent(1.0);
            } else {
                vo.setIsUnlocked(false);
                vo.setObtainCount(0);
                vo.setStarLevel(1);
                vo.setIsEquipped(false);
                vo.setIsViewed(false);

                // 计算未解锁进度
                int current = 0;
                int target = badge.getTargetValue();
                if ("STREAK_DAYS".equalsIgnoreCase(badge.getConditionType())) {
                    current = streakDays;
                } else if ("MASTERED_WORDS".equalsIgnoreCase(badge.getConditionType())) {
                    current = masteredWords;
                }
                vo.setProgressCurrent(current);
                vo.setProgressTarget(target);
                double percent = (target > 0) ? Math.min(1.0, (double) current / target) : 0.0;
                vo.setProgressPercent(percent);
            }
            resultList.add(vo);
        }

        return resultList;
    }

    /**
     * 判定并颁发勋章（支持单次或累积判定）
     */
    public List<UserBadgeVo> checkAndAwardBadges(User user, String conditionType, int currentValue) {
        if (user == null || conditionType == null) {
            return Collections.emptyList();
        }

        List<UserBadgeVo> newlyAwarded = new ArrayList<>();

        for (Badge badge : Badge.values()) {
            if (!badge.getConditionType().equalsIgnoreCase(conditionType)) {
                continue;
            }

            UserBadge existingUb = userBadgeBo.findByUserAndBadgeCode(user.getId(), badge.name());

            if (existingUb == null) {
                // 首次达成检查
                if (currentValue >= badge.getTargetValue()) {
                    try {
                        UserBadge ub = new UserBadge();
                        ub.setId(UUID.randomUUID().toString().replace("-", ""));
                        ub.setUserId(user.getId());
                        ub.setBadgeCode(badge.name());
                        ub.setObtainCount(1);
                        ub.setStarLevel(1);
                        ub.setUnlockedAt(new Date());
                        ub.setIsEquipped(false);
                        ub.setIsViewed(false);
                        ub.setCreateTime(new Date());
                        ub.setUpdateTime(new Date());
                        userBadgeBo.createEntity(ub);

                        // 奖励魔法泡泡
                        if (badge.getRewardBubbles() > 0) {
                            userBo.adjustCowDung(user, badge.getRewardBubbles(), "BadgeUnlock:" + badge.getDisplayName());
                        }

                        UserBadgeVo vo = toUserBadgeVo(ub, badge);
                        vo.setIsUnlocked(true);
                        newlyAwarded.add(vo);
                        log.info("用户 [{}] 首次解锁勋章: {}", user.getUserName(), badge.getDisplayName());
                    } catch (Exception e) {
                        log.error("创建用户勋章失败", e);
                    }
                }
            } else if (badge.isStackable()) {
                // 可多次获得叠层类勋章（如百发百中、极速心流、破晓之翼、夜行学者）
                if (currentValue >= badge.getTargetValue()) {
                    try {
                        int newCount = existingUb.getObtainCount() + 1;
                        existingUb.setObtainCount(newCount);
                        int newStar = calculateStarLevel(newCount);
                        existingUb.setStarLevel(newStar);
                        existingUb.setUpdateTime(new Date());
                        existingUb.setIsViewed(false);
                        userBadgeBo.updateEntity(existingUb);

                        // 每次获得常规魔法泡泡奖励
                        if (badge.getRewardBubbles() > 0) {
                            userBo.adjustCowDung(user, badge.getRewardBubbles(), "BadgeStack:" + badge.getDisplayName());
                        }

                        UserBadgeVo vo = toUserBadgeVo(existingUb, badge);
                        vo.setIsUnlocked(true);
                        newlyAwarded.add(vo);
                        log.info("用户 [{}] 再次获得勋章: {} (×{}, {}星)", user.getUserName(), badge.getDisplayName(), newCount, newStar);
                    } catch (Exception e) {
                        log.error("更新用户勋章失败", e);
                    }
                }
            }
        }

        return newlyAwarded;
    }

    /**
     * 置顶佩戴 / 取消佩戴勋章
     */
    public boolean equipBadge(User user, String badgeCode, boolean equip) {
        if (user == null || badgeCode == null) {
            return false;
        }
        UserBadge ub = userBadgeBo.findByUserAndBadgeCode(user.getId(), badgeCode.trim().toUpperCase());
        if (ub == null) {
            return false;
        }

        if (equip) {
            // 如果置顶佩戴，限制最多佩戴 3 枚，其余先取消
            String countSql = "SELECT COUNT(*) FROM user_badge WHERE user_id = :userId AND is_equipped = TRUE";
            MapSqlParameterSource params = new MapSqlParameterSource("userId", user.getId());
            Long equippedCount = namedParameterJdbcTemplate.queryForObject(countSql, params, Long.class);
            if (equippedCount != null && equippedCount >= 3) {
                // 如果超过3枚，取消最早佩戴的一枚
                String resetSql = "UPDATE user_badge SET is_equipped = FALSE WHERE user_id = :userId ORDER BY update_time ASC LIMIT 1";
                namedParameterJdbcTemplate.update(resetSql, params);
            }
        }

        try {
            ub.setIsEquipped(equip);
            ub.setUpdateTime(new Date());
            userBadgeBo.updateEntity(ub);
            return true;
        } catch (Exception e) {
            log.error("更新勋章佩戴状态失败", e);
            return false;
        }
    }

    private int calculateStarLevel(int count) {
        if (count >= 100) return 5;
        if (count >= 60) return 4;
        if (count >= 30) return 3;
        if (count >= 10) return 2;
        return 1;
    }

    private int getMasteredWordCountOfUser(String userId) {
        String sql = "SELECT COUNT(*) FROM learning_word WHERE user_id = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        Long count = namedParameterJdbcTemplate.queryForObject(sql, params, Long.class);
        return (count != null) ? count.intValue() : 0;
    }

    private UserBadgeVo toUserBadgeVo(UserBadge ub, Badge badge) {
        UserBadgeVo vo = new UserBadgeVo();
        vo.setId(ub.getId());
        vo.setUserId(ub.getUserId());
        vo.setBadgeCode(ub.getBadgeCode());
        vo.setBadge(BadgeVo.fromBadge(badge));
        vo.setObtainCount(ub.getObtainCount());
        vo.setStarLevel(ub.getStarLevel());
        vo.setUnlockedAt(ub.getUnlockedAt());
        vo.setIsEquipped(ub.getIsEquipped());
        vo.setIsViewed(ub.getIsViewed());
        vo.setProgressCurrent(badge.getTargetValue());
        vo.setProgressTarget(badge.getTargetValue());
        vo.setProgressPercent(1.0);
        return vo;
    }
}
