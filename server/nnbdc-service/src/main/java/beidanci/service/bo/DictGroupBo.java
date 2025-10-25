package beidanci.service.bo;

import javax.annotation.PostConstruct;

import java.util.List;

import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.DictGroup;

@Service
@Transactional(rollbackFor = Throwable.class)
public class DictGroupBo extends BaseBo<DictGroup> {
    @PostConstruct
    public void init() {
        setDao(new BaseDao<DictGroup>() {
        });
    }

    // 获取所有单词书分组
    public List<DictGroup> getAllDictGroups() {
        String hql = "from DictGroup order by displayIndex asc";
        Query<DictGroup> query = getSession().createQuery(hql, DictGroup.class);
        query.setCacheable(true);
        return query.list();

    }

}
