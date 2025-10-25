package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.List;

import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.UserGame;
import org.hibernate.Session;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserGameBo extends BaseBo<UserGame> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<UserGame>() {
        });
    }

    public List<UserGame> getUserGamesWithTopScore(final int count) {
        Query<UserGame> query = getSession().createQuery(
                " from UserGame where user.userName not like 'guest%' and user.userName not like 'guess%' and user.userName not like '游客%'"
                        + " order by Score desc ", UserGame.class);
        query.setCacheable(true);
        query.setFirstResult(0);
        query.setMaxResults(count);
        return query.list();
    }

    /**
     * 获取某用户的所有游戏记录。可选新会话，避免在无事务线程中 currentSession 不可用的问题。
     */
    public List<UserGame> getUserGamesOfUser(String userId, boolean openNewSession) {
        Session session = openNewSession ? openSession() : getSession();
        try {
            Query<UserGame> query = session.createQuery(
                    "from UserGame ug where ug.user.id = :userId", UserGame.class);
            query.setParameter("userId", userId);
            return query.list();
        } finally {
            if (openNewSession) {
                session.close();
            }
        }
    }

}
