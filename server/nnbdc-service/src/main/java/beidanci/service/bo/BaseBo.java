package beidanci.service.bo;

import java.io.Serializable;
import java.util.List;

import javax.annotation.Resource;

import org.apache.commons.lang3.tuple.Pair;
import org.hibernate.Session;
import org.hibernate.SessionFactory;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.PagedResults;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.SortRule;
import beidanci.service.po.Po;

public abstract class BaseBo<E extends Po> {
    @Resource(name = "sessionFactory")
    protected SessionFactory sessionFactory;

    protected BaseDao<E> baseDao;

    protected void setDao(BaseDao<E> dao) {
        this.baseDao = dao;
    }

    public BaseDao<E> getDao() {
        return baseDao;
    }

    public PagedResults<E> pagedQuery(E preciseEntity, int pageNo, int pageSize) {
        return pagedQuery(preciseEntity, pageNo, pageSize, null, null);
    }

    /**
     * 分页查询
     *
     * @param sortField 排序字段名
     * @param order     升序还是降序， 可取值 asc 或 desc
     */
    public PagedResults<E> pagedQuery(E preciseEntity, int pageNo, int pageSize, String sortField, String order) {
        return baseDao.pagedQuery(getSession(), preciseEntity, pageNo, pageSize, sortField, order);
    }

    public PagedResults<E> pagedQuery2(E preciseEntity, int fromIndex, int pageSize, List<SortRule> sortRules) {
        return baseDao.pagedQuery2(getSession(), preciseEntity, fromIndex, pageSize, sortRules);
    }

    @SafeVarargs
    public final PagedResults<E> pagedQuery(String hql, int pageNo, int pageSize, Pair<String, Object>... parameters) {
        return baseDao.pagedQuery(getSession(), hql, pageNo, pageSize, parameters);
    }

    @SafeVarargs
    public final E queryUnique(String hql, Pair<String, Object>... parameters) {
        return baseDao.queryUnique(getSession(), hql, parameters);
    }

    @SafeVarargs
    public final PagedResults<E> pagedQuery2(String hql, int fromIndex, int pageSize, Pair<String, Object>... parameters) {
        return baseDao.pagedQuery2(getSession(), hql, fromIndex, pageSize, parameters);
    }

    public List<E> queryAll(E preciseEntity, boolean newSession) {
        return queryAll(preciseEntity, null, null, newSession);
    }

    public List<E> queryAll(E preciseEntity, String sortField, String order, boolean newSession) {
        Session session = newSession ? openSession() : getSession();
        try {
            return baseDao.queryAll(session, preciseEntity, sortField, order);
        } finally {
            if (newSession) {
                session.close();
            }
        }
    }

    public E queryUnique(E preciseEntity) {
        List<E> entities = pagedQuery(preciseEntity, 1, 2).getRows();
        if (entities.isEmpty()) {
            return null;
        } else {
            assert (entities.size() == 1);
            return entities.get(0);
        }
    }

    /**
     * 更新entity，包括entity的所有字段，即使那些值为null的字段也要更新
     */
    @Transactional
    public void updateEntity(E entity) throws IllegalArgumentException, IllegalAccessException {
        baseDao.updateEntity(getSession(), entity, false, true);
    }

    @Transactional
    public void updateEntity(E entity, boolean updateUpdateTime) throws IllegalAccessException {
        baseDao.updateEntity(getSession(), entity, false, updateUpdateTime);
    }

    @Transactional
    public void deleteEntity(E entity) {
        baseDao.deleteEntity(getSession(), entity);
    }

    @Transactional
    public void deleteById(Serializable id) {
        E entity = findById(id, false);
        deleteEntity(entity);
    }

    @Transactional
    public void createEntity(E entity) {
        baseDao.createEntity(getSession(), entity);
    }

    @Transactional(readOnly = true)
    public E findById(Serializable id) {
        return findById(id, false);
    }

    public E findById(Serializable id, boolean newSession) {
        Session session = newSession ? openSession() : getSession();
        try {
            return baseDao.getEntityById(session, id);
        } finally {
            if (newSession) {
                session.close();
            }
        }
    }

    public Session getSession() {
        return sessionFactory.getCurrentSession();
    }

    public Session openSession() {
        return sessionFactory.openSession();
    }

    /**
     * 从session缓存中清除指定对象
     */
    public void evict(E entity) {
        Session session = getSession();
        session.evict(entity);
    }
}
