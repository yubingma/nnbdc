package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.Date;
import java.util.List;

import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.User;
import beidanci.service.po.UserStudyRecord;

@Service
@Transactional(rollbackFor = Throwable.class)
public class StudyRecordBo extends BaseBo<UserStudyRecord> {
    @PostConstruct
    public void init() {
        setDao(new BaseDao<UserStudyRecord>() {
        });
    }

    public List<UserStudyRecord> getStudyRecords(User user, Date startDate, Date endDate) {
        String hql = "from UserStudyRecord sr where id.userId = :userId and theDate >= :startDate and theDate <= :endDate";

        Query<UserStudyRecord> query = getSession().createQuery(hql, UserStudyRecord.class);
        query.setParameter("userId", user.getId());
        query.setParameter("startDate", startDate);
        query.setParameter("endDate", endDate);
        return query.list();
    }
}
