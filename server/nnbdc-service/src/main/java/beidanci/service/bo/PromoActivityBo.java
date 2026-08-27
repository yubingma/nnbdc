package beidanci.service.bo;

import java.util.List;
import javax.annotation.PostConstruct;
import org.apache.commons.lang3.tuple.Pair;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.PromoActivity;

@Service
@Transactional(rollbackFor = Throwable.class)
public class PromoActivityBo extends BaseBo<PromoActivity> {
    
    @PostConstruct
    public void init() {
        setDao(new BaseDao<PromoActivity>() {});
    }

    public PromoActivity findByCode(String code) {
        if (code == null) {
            return null;
        }
        String sql = "SELECT * FROM promo_activity WHERE UPPER(activity_code) = UPPER(:code)";
        return queryUnique(sql, Pair.of("code", code.trim()));
    }

    /**
     * 从文本内容中匹配活动兑换码（支持用户在内容中夹带文字，忽略大小写，优先匹配最长兑换码）
     */
    public PromoActivity findMatchingActivityInContent(String content) {
        if (content == null || content.trim().isEmpty()) {
            return null;
        }
        List<PromoActivity> allActivities = queryAll(null, null, null, false);
        if (allActivities == null || allActivities.isEmpty()) {
            return null;
        }
        String upperContent = content.toUpperCase();
        PromoActivity bestMatch = null;
        for (PromoActivity act : allActivities) {
            if (act.getActivityCode() != null && !act.getActivityCode().trim().isEmpty()) {
                String code = act.getActivityCode().trim().toUpperCase();
                if (upperContent.contains(code)) {
                    if (bestMatch == null || code.length() > bestMatch.getActivityCode().trim().length()) {
                        bestMatch = act;
                    }
                }
            }
        }
        return bestMatch;
    }

    public PromoActivity getLatestActiveActivity() {
        String sql = "SELECT * FROM promo_activity " +
                     "WHERE is_active IS TRUE " +
                     "AND (start_time IS NULL OR start_time <= NOW()) " +
                     "AND (end_time IS NULL OR end_time > NOW()) " +
                     "AND (max_redemptions IS NULL OR max_redemptions = 0 OR redemption_count < max_redemptions) " +
                     "ORDER BY create_time DESC LIMIT 1";
        return queryUnique(sql);
    }
}
