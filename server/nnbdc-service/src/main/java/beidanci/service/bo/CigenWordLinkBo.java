package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.List;

import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.CigenWordLink;

@Service
@Transactional(rollbackFor = Throwable.class)
public class CigenWordLinkBo extends BaseBo<CigenWordLink> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<CigenWordLink>() {
        });
    }

    public List<CigenWordLink> findByWordId(Integer wordId) {
        String hql = "from CigenWordLink where id.wordId = :wordId";
        Query<CigenWordLink> query = getSession().createQuery(hql, CigenWordLink.class);
        query.setParameter("wordId", wordId);
        return query.getResultList();
    }


}
