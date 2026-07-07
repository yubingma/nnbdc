package beidanci.service.bo;

import java.util.Date;
import javax.annotation.PostConstruct;
import org.apache.commons.lang3.tuple.Pair;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.PromoActivity;
import beidanci.service.po.PromoRedemption;
import beidanci.service.po.User;

@Service
@Transactional(rollbackFor = Throwable.class)
public class PromoRedemptionBo extends BaseBo<PromoRedemption> {

    @Autowired
    private UserBo userBo;

    @Autowired
    private PromoActivityBo promoActivityBo;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<PromoRedemption>() {});
    }

    public boolean hasRedeemed(String userId, String activityId) {
        if (userId == null || activityId == null) {
            return false;
        }
        String sql = "SELECT * FROM promo_redemption WHERE user_id = :userId AND activity_id = :activityId";
        PromoRedemption redemption = queryUnique(sql, 
                Pair.of("userId", userId), 
                Pair.of("activityId", activityId));
        return redemption != null;
    }

    @Transactional(rollbackFor = Throwable.class)
    public User redeem(User user, PromoActivity activity) throws IllegalAccessException {
        // 1. 确保版本记录存在并加锁
        userBo.getUserDbVersionWithLock(user.getId());

        // 2. 更新用户为会员
        user.setPremiumOverrideEnabled(true);
        user.setPremiumOverrideUpdateTime(new Date());
        user.setPremiumOverrideDuration(activity.getDuration());
        user.setPremiumOverrideReason("兑换活动码: " + activity.getActivityCode());
        userBo.updateEntity(user);
        userBo.logUserUpdateForSync(user);

        // 3. 记录兑换记录
        PromoRedemption redemption = new PromoRedemption();
        redemption.setUserId(user.getId());
        redemption.setActivityId(activity.getId());
        redemption.setRedeemTime(new Date());
        createEntity(redemption);

        // 4. 更新活动兑换次数
        activity.setRedemptionCount(activity.getRedemptionCount() + 1);
        promoActivityBo.updateEntity(activity);

        return user;
    }
}
