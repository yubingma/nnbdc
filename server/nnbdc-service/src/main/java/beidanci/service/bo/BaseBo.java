package beidanci.service.bo;

import java.io.Serializable;
import java.util.List;

import javax.annotation.Resource;

import org.apache.commons.lang3.tuple.Pair;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.PagedResults;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.SortRule;
import beidanci.service.po.Po;

public abstract class BaseBo<E extends Po> {
    @Resource
    protected JdbcTemplate jdbcTemplate;

    protected BaseDao<E> baseDao;

    protected void setDao(BaseDao<E> dao) {
        this.baseDao = dao;
        // 设置 JdbcTemplate 到 DAO
        if (dao != null && jdbcTemplate != null) {
            dao.setJdbcTemplate(jdbcTemplate);
        }
    }

    public BaseDao<E> getDao() {
        return baseDao;
    }

    public JdbcTemplate getJdbcTemplate() {
        return jdbcTemplate;
    }

    public PagedResults<E> pagedQuery(E preciseEntity, int pageNo, int pageSize) {
        return pagedQuery(preciseEntity, pageNo, pageSize, null, null);
    }

    /**
     * 分页查询
     *
     * @param sortField 排序字段名
     * @param order     升序还是降序，可取值 asc 或 desc
     */
    public PagedResults<E> pagedQuery(E preciseEntity, int pageNo, int pageSize, String sortField, String order) {
        return baseDao.pagedQuery(jdbcTemplate, preciseEntity, pageNo, pageSize, sortField, order);
    }

    public PagedResults<E> pagedQuery2(E preciseEntity, int fromIndex, int pageSize, List<SortRule> sortRules) {
        return baseDao.pagedQuery2(jdbcTemplate, preciseEntity, fromIndex, pageSize, sortRules);
    }

    /**
     * 使用 SQL 进行分页查询
     *
     * @param sql        SQL 语句
     * @param pageNo     页码（从 1 开始）
     * @param pageSize   每页大小
     * @param parameters 命名参数数组，每个参数为 Pair<参数名，参数值>
     * @return 分页结果
     */
    @SafeVarargs
    public final PagedResults<E> pagedQuery(String sql, int pageNo, int pageSize, Pair<String, Object>... parameters) {
        // 该方法委托给 BaseDao。注意：必须通过 getDao() 和 getJdbcTemplate() 访问，
        // 否则在 Spring 代理对象上调用 final 方法时会出现字段为 null 的情况。
        return getDao().pagedQuery(getJdbcTemplate(), sql, pageNo, pageSize, parameters);
    }

    /**
     * 使用 SQL 查询唯一记录
     *
     * @param sql        SQL 语句
     * @param parameters 命名参数数组，每个参数为 Pair<参数名，参数值>
     * @return 唯一记录，如果没有找到则返回 null
     */
    @SafeVarargs
    public final E queryUnique(String sql, Pair<String, Object>... parameters) {
        return getDao().queryUnique(getJdbcTemplate(), sql, parameters);
    }

    /**
     * 使用 SQL 进行分页查询（从指定索引开始）
     *
     * @param sql        SQL 语句
     * @param fromIndex  起始索引
     * @param pageSize   每页大小
     * @param parameters 命名参数数组，每个参数为 Pair<参数名，参数值>
     * @return 分页结果
     */
    @SafeVarargs
    public final PagedResults<E> pagedQuery2(String sql, int fromIndex, int pageSize,
            Pair<String, Object>... parameters) {
        return getDao().pagedQuery2(getJdbcTemplate(), sql, fromIndex, pageSize, parameters);
    }

    public List<E> queryAll(E preciseEntity, boolean newSession) {
        return queryAll(preciseEntity, null, null, newSession);
    }

    public List<E> queryAll(E preciseEntity, String sortField, String order, boolean newSession) {
        // JDBC 不需要管理 Session，直接查询
        return baseDao.queryAll(jdbcTemplate, preciseEntity, sortField, order);
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
        baseDao.updateEntity(jdbcTemplate, entity, false, true);
    }

    @Transactional
    public void updateEntity(E entity, boolean updateUpdateTime) throws IllegalAccessException {
        baseDao.updateEntity(jdbcTemplate, entity, false, updateUpdateTime);
    }

    @Transactional
    public void deleteEntity(E entity) {
        baseDao.deleteEntity(jdbcTemplate, entity);
    }

    @Transactional
    public void deleteById(Serializable id) {
        E entity = findById(id, false);
        if (entity != null) {
            deleteEntity(entity);
        }
    }

    @Transactional
    public void createEntity(E entity) {
        baseDao.createEntity(jdbcTemplate, entity);
    }

    @Transactional(readOnly = true)
    public E findById(Serializable id) {
        return findById(id, false);
    }

    public E findById(Serializable id, boolean newSession) {
        // JDBC 不需要管理 Session，直接查询
        return baseDao.getEntityById(jdbcTemplate, id);
    }

    /**
     * JDBC 不需要 evict 操作，此方法保留以保持接口兼容性
     */
    public void evict(E entity) {
        // JDBC 不需要管理 Session 缓存，此方法为空实现
    }
}
