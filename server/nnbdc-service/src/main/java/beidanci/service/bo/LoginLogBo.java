package beidanci.service.bo;
import javax.annotation.PostConstruct;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.LoginLog;
import beidanci.service.po.User;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(rollbackFor = Throwable.class)
public class LoginLogBo extends BaseBo<LoginLog> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<LoginLog>() {
        });
    }

    public void cleanLoginLogs(User user) {
        // 后面的单词前移
        String hql = "delete LoginLog where user=:user";
        javax.persistence.Query query = getSession().createQuery(hql);
        query.setParameter("user", user);
        query.executeUpdate();
    }
}
