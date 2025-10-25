package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.List;

import org.hibernate.Session;
import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.WordAdditionalInfo;

@Service
@Transactional(rollbackFor = Throwable.class)
public class WordAdditionalInfoBo extends BaseBo<WordAdditionalInfo> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<WordAdditionalInfo>() {
        });
    }

    public List<WordAdditionalInfo> findByWordSpell(String wordSpell) {
        Session session = getSession();
        String hql = "  from WordAdditionalInfo where word.spell = :spell ";
        Query<WordAdditionalInfo> query = session.createQuery(hql, WordAdditionalInfo.class);
        query.setParameter("spell", wordSpell);
        return query.list();
    }
}
