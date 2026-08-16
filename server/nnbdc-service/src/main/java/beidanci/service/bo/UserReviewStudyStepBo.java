package beidanci.service.bo;

import javax.annotation.PostConstruct;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.UserReviewStudyStep;

/**
 * 旧词（复习词）三组学习规则条目 BO
 */
@Service
@Transactional(rollbackFor = Throwable.class)
public class UserReviewStudyStepBo extends BaseBo<UserReviewStudyStep> {

    @PostConstruct
    public void init() {
        setDao(new BaseDao<UserReviewStudyStep>() {
        });
    }
}
