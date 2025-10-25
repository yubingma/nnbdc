package beidanci.service.dao;

import java.io.Serializable;
import java.lang.reflect.Field;
import java.lang.reflect.ParameterizedType;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

import org.apache.commons.lang.StringUtils;
import org.apache.commons.lang3.tuple.Pair;
import org.hibernate.Criteria;
import org.hibernate.Session;
import org.hibernate.criterion.CriteriaSpecification;
import org.hibernate.criterion.Order;
import org.hibernate.criterion.Projections;
import org.hibernate.criterion.Restrictions;
import org.hibernate.query.Query;

import beidanci.api.model.PagedResults;
import beidanci.service.UuidSetter;
import beidanci.service.po.Po;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.ReflectionUtil;
import beidanci.util.Utils;

/**
 * DAO基类，支持基本的CRUD、分页、模糊查询 <br>
 * 注意：本类有状态，不要以单例使用
 *
 * @param <E>
 * @author MaYubing
 */
public abstract class BaseDao<E extends Po> {

    private final ParameterizedType parameterizedType = (ParameterizedType) getClass().getGenericSuperclass();

    @SuppressWarnings("unchecked")
    private final Class<E> valueClass = (Class<E>) (parameterizedType).getActualTypeArguments()[0];

    public void createEntity(Session session, E entity) {
        Date now = new Date();
        UuidSetter.setUuidIfNotPresent(entity);
        entity.setCreateTime(now);
        entity.setUpdateTime(now);
        session.persist(entity);
    }

    public List<E> queryAll(Session session, E preciseEntity, String sortField, String order) {
        return pagedQuery(session, preciseEntity, 1, Integer.MAX_VALUE, sortField, order).getRows();
    }

    @SafeVarargs
    public final PagedResults<E> pagedQuery(Session session, String hql, int pageNo, int pageSize, Pair<String, Object>... parameters) {
        Query<E> query = session.createQuery(hql, valueClass);
        for (Pair<String, Object> param : parameters) {
            query.setParameter(param.getLeft(), param.getRight());
        }
        List<E> rows = query.setFirstResult((pageNo - 1) * pageSize).setMaxResults(pageSize).list();
        Query<Long> countQuery = session.createQuery("select count(0) " + hql, Long.class);
        for (Pair<String, Object> param : parameters) {
            countQuery.setParameter(param.getLeft(), param.getRight());
        }
        Long totalCount = countQuery.uniqueResult();
        return new PagedResults<>(totalCount.intValue(), rows);
    }

    @SafeVarargs
    public final E queryUnique(Session session, String hql, Pair<String, Object>... parameters) {
        Query<E> query = session.createQuery(hql, valueClass);
        for (Pair<String, Object> param : parameters) {
            query.setParameter(param.getLeft(), param.getRight());
        }
        E result = query.uniqueResult();
        return result;
    }

    @SafeVarargs
    public final PagedResults<E> pagedQuery2(Session session, String hql, int fromIndex, int pageSize, Pair<String, Object>... parameters) {
        Query<E> query = session.createQuery(hql, valueClass);
        for (Pair<String, Object> param : parameters) {
            query.setParameter(param.getLeft(), param.getRight());
        }
        List<E> rows = query.setFirstResult(fromIndex).setMaxResults(pageSize).list();
        Query<Long> countQuery = session.createQuery("select count(0) " + hql, Long.class);
        for (Pair<String, Object> param : parameters) {
            countQuery.setParameter(param.getLeft(), param.getRight());
        }
        Long totalCount = countQuery.uniqueResult();
        return new PagedResults<>(totalCount.intValue(), rows);
    }

    @SuppressWarnings("unchecked")
    public PagedResults<E> pagedQuery(Session session, E preciseEntity, int pageNo, int pageSize, String sortField, String order) {
        assert (pageNo >= 0 && pageSize >= 1);

        List<SortRule> sortRules = null;
        if (!StringUtils.isEmpty(sortField)) {
            sortRules = new ArrayList<>();
            SortRule sortRule = SortRule.makeSortRule(sortField + " " + (StringUtils.isEmpty(order) ? "asc" : order));
            sortRules.add(sortRule);
        }

        PagedResults<E> pagedResults = new PagedResults<>();

        @SuppressWarnings("deprecation")
        Criteria criteria = session.createCriteria(valueClass);

        if (preciseEntity != null) {
            addPreciseRestrictions(preciseEntity, criteria);
        }

        Integer total = ((Long) criteria.setProjection(Projections.rowCount()).uniqueResult()).intValue();
        pagedResults.setTotal(total);
        criteria.setProjection(null);

        if (sortRules != null) {
            for (SortRule sortRule : sortRules) {
                String fieldName = sortRule.getFieldName();

                // 属性名中可能含有.号（即关联对象的属性），需要创建Alias才能正常工作
                String[] parts = fieldName.split("\\.");
                if (parts.length >= 2) {
                    for (int i = 0; i <= parts.length - 2; i++) {
                        criteria.createAlias(parts[i], parts[i]);
                    }
                }

                if (sortRule.getAsc()) {
                    criteria.addOrder(Order.asc(fieldName));
                } else {
                    criteria.addOrder(Order.desc(fieldName));
                }
            }
        }

        if (pageSize != Integer.MAX_VALUE) {
            int offset = (pageSize * (pageNo - 1));
            offset = (Math.max(0, offset));
            criteria.setFirstResult(offset);
            criteria.setMaxResults(pageSize);
        }

        criteria.setResultTransformer(CriteriaSpecification.DISTINCT_ROOT_ENTITY);
        List<E> entities = Utils.abstractEntityFromList(criteria.list(), valueClass);
        pagedResults.setRows(entities);

        return pagedResults;
    }

    @SuppressWarnings("unchecked")
    public PagedResults<E> pagedQuery2(Session session, E preciseEntity, int fromIndex, int pageSize, List<SortRule> sortRules) {
        assert (fromIndex >= 0 && pageSize >= 1);

        PagedResults<E> pagedResults = new PagedResults<>();

        @SuppressWarnings("deprecation")
        Criteria criteria = session.createCriteria(valueClass);

        if (preciseEntity != null) {
            addPreciseRestrictions(preciseEntity, criteria);
        }

        Integer total = ((Long) criteria.setProjection(Projections.rowCount()).uniqueResult()).intValue();
        pagedResults.setTotal(total);
        criteria.setProjection(null);

        if (sortRules != null) {
            for (SortRule sortRule : sortRules) {
                String fieldName = sortRule.getFieldName();

                // 属性名中可能含有.号（即关联对象的属性），需要创建Alias才能正常工作
                String[] parts = fieldName.split("\\.");
                if (parts.length >= 2) {
                    for (int i = 0; i <= parts.length - 2; i++) {
                        criteria.createAlias(parts[i], parts[i]);
                    }
                }

                if (sortRule.getAsc()) {
                    criteria.addOrder(Order.asc(fieldName));
                } else {
                    criteria.addOrder(Order.desc(fieldName));
                }
            }
        }

        if (pageSize != Integer.MAX_VALUE) {
            criteria.setFirstResult(fromIndex);
            criteria.setMaxResults(pageSize);
        }

        criteria.setResultTransformer(CriteriaSpecification.DISTINCT_ROOT_ENTITY);
        List<E> entities = Utils.abstractEntityFromList(criteria.list(), valueClass);
        pagedResults.setRows(entities);

        return pagedResults;
    }

    /**
     * 更新entity，包括entity的所有字段，即使那些值为null的字段也要更新
     */
    @SuppressWarnings("unchecked")
    public void updateEntity(Session session, E entity, boolean flush, boolean updateUpdateTime)
            throws IllegalArgumentException, IllegalAccessException {
        if (entity.getCreateTime() == null) {
            E obj = (E) session.load(entity.getClass(), BeanUtils.getIdOfPo(entity));
            entity.setCreateTime(obj.getCreateTime());
        }
        if (updateUpdateTime) {
            entity.setUpdateTime(new Date());
        }
        session.merge(entity);
        if (flush) {
            session.flush();
        }
    }


    public void deleteEntity(Session session, E entity) {
        session.delete(entity);
    }

    public E getEntityById(Session session, Serializable id) {
        E entity = session.get(valueClass, id);
        return entity;
    }

    private void addPreciseRestrictions(E preciseEntity, Criteria criteria) {
        List<Field> fields = BeanUtils.getFields(valueClass, true);
        String fieldName;
        Object fieldValue;
        for (Field field : fields) {
            fieldName = field.getName();
            fieldValue = ReflectionUtil.getFieldValue(preciseEntity, fieldName);
            if (null != fieldValue) {
                criteria.add(Restrictions.eq(fieldName, fieldValue));
            }
        }
    }

    /**
     * 从session缓存中清除指定对象
     */
    public void evict(Session session, E entity) {
        session.evict(entity);
    }
}
