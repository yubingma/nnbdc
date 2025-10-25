package beidanci.service.bo;

import javax.annotation.PostConstruct;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.Event;
import beidanci.service.po.User;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(rollbackFor = Throwable.class)
public class EventBo extends BaseBo<Event> {
    @PostConstruct
    public void init() {
        setDao(new BaseDao<Event>() {
        });
    }

    public void clearUserEvents(User user) {
        String hql = "delete Event where user=:user";
        javax.persistence.Query query = getSession().createQuery(hql);
        query.setParameter("user", user);
        query.executeUpdate();
    }
}
