package beidanci.service.bo;

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
