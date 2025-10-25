package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.Date;
import java.util.List;

import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.User;
import beidanci.service.po.UserSnapshotDaily;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserSnapshotDailyBo extends BaseBo<UserSnapshotDaily> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<UserSnapshotDaily>() {
        });
    }

    public List<UserSnapshotDaily> getUserSnapshotDailys(User user, Date startDate, Date endDate) {
        String hql = "from UserSnapshotDaily where user = :user and theDate >= :startDate and theDate <= :endDate";

        Query<UserSnapshotDaily> query = getSession().createQuery(hql, UserSnapshotDaily.class);
        query.setParameter("user", user);
        query.setParameter("startDate", startDate);
        query.setParameter("endDate", endDate);
        return query.list();
    }
}
