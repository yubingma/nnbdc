package beidanci.service.dao;

import java.io.Serializable;
import java.lang.reflect.Field;
import java.lang.reflect.ParameterizedType;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

import org.apache.commons.lang.StringUtils;
import org.apache.commons.lang3.tuple.Pair;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

import beidanci.api.model.PagedResults;
import beidanci.service.UuidSetter;
import beidanci.service.po.Po;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.ReflectionUtil;

import javax.persistence.ManyToOne;
import javax.persistence.OneToMany;
import javax.persistence.ManyToMany;
import javax.persistence.OneToOne;

/**
 * DAO基类，支持基本的CRUD、分页、模糊查询 <br>
 * 使用 Spring JDBC + RowMapper 替代 Hibernate
 * 
 * @param <E>
 * @author MaYubing
 */
public abstract class BaseDao<E extends Po> {

    private final ParameterizedType parameterizedType = (ParameterizedType) getClass().getGenericSuperclass();

    @SuppressWarnings("unchecked")
    protected final Class<E> valueClass = (Class<E>) (parameterizedType).getActualTypeArguments()[0];
    
    protected JdbcTemplate jdbcTemplate;
    protected NamedParameterJdbcTemplate namedParameterJdbcTemplate;
    protected EntityRowMapper<E> rowMapper;
    
    /**
     * 设置 JdbcTemplate（由子类或配置类注入）
     */
    public void setJdbcTemplate(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
        this.namedParameterJdbcTemplate = new NamedParameterJdbcTemplate(jdbcTemplate);
        this.rowMapper = new EntityRowMapper<>(valueClass);
    }

    /**
     * 创建实体
     */
    public void createEntity(JdbcTemplate jdbcTemplate, E entity) {
        if (this.jdbcTemplate == null) {
            setJdbcTemplate(jdbcTemplate);
        }
        
        Date now = new Date();
        UuidSetter.setUuidIfNotPresent(entity);
        entity.setCreateTime(now);
        entity.setUpdateTime(now);
        
        String tableName = EntityTableInfo.getTableName(valueClass);
        Field idField = EntityTableInfo.getIdField(valueClass);
        
        // 构建 INSERT SQL
        StringBuilder sql = new StringBuilder("INSERT INTO ");
        sql.append(tableName).append(" (");
        
        List<Field> fields = BeanUtils.getFields(valueClass, true);
        List<String> columnNames = new ArrayList<>();
        List<Object> values = new ArrayList<>();
        
        for (Field field : fields) {
            // 跳过关联字段和主键（如果主键已设置）
            if (isAssociationField(field)) {
                continue;
            }
            
            String columnName = EntityTableInfo.getColumnName(field);
            columnNames.add(columnName);
            
            try {
                field.setAccessible(true);
                Object value = field.get(entity);
                values.add(value);
            } catch (IllegalAccessException e) {
                throw new RuntimeException("获取字段值失败: " + field.getName(), e);
            }
        }
        
        sql.append(String.join(", ", columnNames));
        sql.append(") VALUES (");
        sql.append(String.join(", ", columnNames.stream().map(c -> "?").toList()));
        sql.append(")");
        
        jdbcTemplate.update(sql.toString(), values.toArray());
    }

    /**
     * 查询所有记录
     */
    public List<E> queryAll(JdbcTemplate jdbcTemplate, E preciseEntity, String sortField, String order) {
        return pagedQuery(jdbcTemplate, preciseEntity, 1, Integer.MAX_VALUE, sortField, order).getRows();
    }

    /**
     * 使用 SQL 进行分页查询（HQL 需要转换为 SQL）
     */
    @SafeVarargs
    public final PagedResults<E> pagedQuery(JdbcTemplate jdbcTemplate, String sql, int pageNo, int pageSize, Pair<String, Object>... parameters) {
        if (this.jdbcTemplate == null) {
            setJdbcTemplate(jdbcTemplate);
        }
        
        // 转换 HQL 为 SQL（简单处理，复杂情况需要手动转换）
        String convertedSql = convertHqlToSql(sql);
        
        // 构建参数映射
        MapSqlParameterSource paramSource = new MapSqlParameterSource();
        for (Pair<String, Object> param : parameters) {
            paramSource.addValue(param.getLeft(), param.getRight());
        }
        
        // 查询总数
        String countSql = "SELECT COUNT(*) FROM (" + convertedSql + ") AS count_query";
        Integer total = namedParameterJdbcTemplate.queryForObject(countSql, paramSource, Integer.class);
        
        // 分页查询
        String pagedSql = convertedSql + " LIMIT :limit OFFSET :offset";
        paramSource.addValue("limit", pageSize);
        paramSource.addValue("offset", (pageNo - 1) * pageSize);
        
        List<E> rows = namedParameterJdbcTemplate.query(pagedSql, paramSource, rowMapper);
        
        return new PagedResults<>(total != null ? total : 0, rows);
    }

    /**
     * 使用 SQL 查询唯一记录
     */
    @SafeVarargs
    public final E queryUnique(JdbcTemplate jdbcTemplate, String sql, Pair<String, Object>... parameters) {
        if (this.jdbcTemplate == null) {
            setJdbcTemplate(jdbcTemplate);
        }
        
        String convertedSql = convertHqlToSql(sql);
        
        MapSqlParameterSource paramSource = new MapSqlParameterSource();
        for (Pair<String, Object> param : parameters) {
            paramSource.addValue(param.getLeft(), param.getRight());
        }
        
        List<E> results = namedParameterJdbcTemplate.query(convertedSql, paramSource, rowMapper);
        return results.isEmpty() ? null : results.get(0);
    }

    /**
     * 使用 SQL 进行分页查询（从指定索引开始）
     */
    @SafeVarargs
    public final PagedResults<E> pagedQuery2(JdbcTemplate jdbcTemplate, String sql, int fromIndex, int pageSize, Pair<String, Object>... parameters) {
        if (this.jdbcTemplate == null) {
            setJdbcTemplate(jdbcTemplate);
        }
        
        String convertedSql = convertHqlToSql(sql);
        
        MapSqlParameterSource paramSource = new MapSqlParameterSource();
        for (Pair<String, Object> param : parameters) {
            paramSource.addValue(param.getLeft(), param.getRight());
        }
        
        // 查询总数
        String countSql = "SELECT COUNT(*) FROM (" + convertedSql + ") AS count_query";
        Integer total = namedParameterJdbcTemplate.queryForObject(countSql, paramSource, Integer.class);
        
        // 分页查询
        String pagedSql = convertedSql + " LIMIT :limit OFFSET :offset";
        paramSource.addValue("limit", pageSize);
        paramSource.addValue("offset", fromIndex);
        
        List<E> rows = namedParameterJdbcTemplate.query(pagedSql, paramSource, rowMapper);
        
        return new PagedResults<>(total != null ? total : 0, rows);
    }

    /**
     * 基于实体对象进行分页查询
     */
    public PagedResults<E> pagedQuery(JdbcTemplate jdbcTemplate, E preciseEntity, int pageNo, int pageSize, String sortField, String order) {
        if (this.jdbcTemplate == null) {
            setJdbcTemplate(jdbcTemplate);
        }
        
        assert (pageNo >= 0 && pageSize >= 1);

        String tableName = EntityTableInfo.getTableName(valueClass);
        StringBuilder sql = new StringBuilder("SELECT * FROM ").append(tableName).append(" WHERE 1=1");
        
        List<Object> params = new ArrayList<>();
        int paramIndex = 1;
        
        // 添加精确查询条件
        if (preciseEntity != null) {
            List<Field> fields = BeanUtils.getFields(valueClass, true);
            for (Field field : fields) {
                if (isAssociationField(field)) {
                    continue;
                }
                
                try {
                    Object fieldValue = ReflectionUtil.getFieldValue(preciseEntity, field.getName());
                    if (fieldValue != null) {
                        String columnName = EntityTableInfo.getColumnName(field);
                        sql.append(" AND ").append(columnName).append(" = ?");
                        params.add(fieldValue);
                    }
                } catch (Exception e) {
                    // 忽略获取字段值失败的情况
                }
            }
        }
        
        // 添加排序
        if (!StringUtils.isEmpty(sortField)) {
            String columnName = getColumnNameFromFieldName(sortField);
            sql.append(" ORDER BY ").append(columnName);
            if (!StringUtils.isEmpty(order) && "desc".equalsIgnoreCase(order)) {
                sql.append(" DESC");
            } else {
                sql.append(" ASC");
            }
        }
        
        // 查询总数
        String countSql = "SELECT COUNT(*) FROM (" + sql.toString() + ") AS count_query";
        Integer total = jdbcTemplate.queryForObject(countSql, params.toArray(), Integer.class);
        
        // 分页查询
        sql.append(" LIMIT ? OFFSET ?");
        params.add(pageSize);
        params.add((pageNo - 1) * pageSize);
        
        List<E> rows = jdbcTemplate.query(sql.toString(), params.toArray(), rowMapper);
        
        return new PagedResults<>(total != null ? total : 0, rows);
    }

    /**
     * 基于实体对象进行分页查询（从指定索引开始）
     */
    public PagedResults<E> pagedQuery2(JdbcTemplate jdbcTemplate, E preciseEntity, int fromIndex, int pageSize, List<SortRule> sortRules) {
        if (this.jdbcTemplate == null) {
            setJdbcTemplate(jdbcTemplate);
        }
        
        assert (fromIndex >= 0 && pageSize >= 1);

        String tableName = EntityTableInfo.getTableName(valueClass);
        StringBuilder sql = new StringBuilder("SELECT * FROM ").append(tableName).append(" WHERE 1=1");
        
        List<Object> params = new ArrayList<>();
        
        // 添加精确查询条件
        if (preciseEntity != null) {
            List<Field> fields = BeanUtils.getFields(valueClass, true);
            for (Field field : fields) {
                if (isAssociationField(field)) {
                    continue;
                }
                
                try {
                    Object fieldValue = ReflectionUtil.getFieldValue(preciseEntity, field.getName());
                    if (fieldValue != null) {
                        String columnName = EntityTableInfo.getColumnName(field);
                        sql.append(" AND ").append(columnName).append(" = ?");
                        params.add(fieldValue);
                    }
                } catch (Exception e) {
                    // 忽略获取字段值失败的情况
                }
            }
        }
        
        // 添加排序
        if (sortRules != null && !sortRules.isEmpty()) {
            sql.append(" ORDER BY ");
            List<String> orderParts = new ArrayList<>();
            for (SortRule sortRule : sortRules) {
                String columnName = getColumnNameFromFieldName(sortRule.getFieldName());
                orderParts.add(columnName + (sortRule.getAsc() ? " ASC" : " DESC"));
            }
            sql.append(String.join(", ", orderParts));
        }
        
        // 查询总数
        String countSql = "SELECT COUNT(*) FROM (" + sql.toString() + ") AS count_query";
        Integer total = jdbcTemplate.queryForObject(countSql, params.toArray(), Integer.class);
        
        // 分页查询
        sql.append(" LIMIT ? OFFSET ?");
        params.add(pageSize);
        params.add(fromIndex);
        
        List<E> rows = jdbcTemplate.query(sql.toString(), params.toArray(), rowMapper);
        
        return new PagedResults<>(total != null ? total : 0, rows);
    }

    /**
     * 更新实体
     */
    public void updateEntity(JdbcTemplate jdbcTemplate, E entity, boolean flush, boolean updateUpdateTime)
            throws IllegalArgumentException, IllegalAccessException {
        if (this.jdbcTemplate == null) {
            setJdbcTemplate(jdbcTemplate);
        }
        
        if (updateUpdateTime) {
            entity.setUpdateTime(new Date());
        }
        
        String tableName = EntityTableInfo.getTableName(valueClass);
        Field idField = EntityTableInfo.getIdField(valueClass);
        
        // 如果 createTime 为空，从数据库查询
        if (entity.getCreateTime() == null) {
            try {
                idField.setAccessible(true);
                Serializable id = (Serializable) idField.get(entity);
                E existing = getEntityById(jdbcTemplate, id);
                if (existing != null) {
                    entity.setCreateTime(existing.getCreateTime());
                }
            } catch (Exception e) {
                // 忽略
            }
        }
        
        // 构建 UPDATE SQL
        StringBuilder sql = new StringBuilder("UPDATE ");
        sql.append(tableName).append(" SET ");
        
        List<Field> fields = BeanUtils.getFields(valueClass, true);
        List<String> setParts = new ArrayList<>();
        List<Object> values = new ArrayList<>();
        
        for (Field field : fields) {
            if (isAssociationField(field) || field.equals(idField)) {
                continue;
            }
            
            String columnName = EntityTableInfo.getColumnName(field);
            setParts.add(columnName + " = ?");
            
            try {
                field.setAccessible(true);
                Object value = field.get(entity);
                values.add(value);
            } catch (IllegalAccessException e) {
                throw new RuntimeException("获取字段值失败: " + field.getName(), e);
            }
        }
        
        sql.append(String.join(", ", setParts));
        
        // 添加 WHERE 条件
        try {
            idField.setAccessible(true);
            Serializable id = (Serializable) idField.get(entity);
            String idColumnName = EntityTableInfo.getColumnName(idField);
            sql.append(" WHERE ").append(idColumnName).append(" = ?");
            values.add(id);
        } catch (IllegalAccessException e) {
            throw new RuntimeException("获取主键值失败", e);
        }
        
        jdbcTemplate.update(sql.toString(), values.toArray());
    }

    /**
     * 删除实体
     */
    public void deleteEntity(JdbcTemplate jdbcTemplate, E entity) {
        if (this.jdbcTemplate == null) {
            setJdbcTemplate(jdbcTemplate);
        }
        
        String tableName = EntityTableInfo.getTableName(valueClass);
        Field idField = EntityTableInfo.getIdField(valueClass);
        
        try {
            idField.setAccessible(true);
            Serializable id = (Serializable) idField.get(entity);
            String idColumnName = EntityTableInfo.getColumnName(idField);
            String sql = "DELETE FROM " + tableName + " WHERE " + idColumnName + " = ?";
            jdbcTemplate.update(sql, id);
        } catch (IllegalAccessException e) {
            throw new RuntimeException("获取主键值失败", e);
        }
    }

    /**
     * 根据 ID 查询实体
     */
    public E getEntityById(JdbcTemplate jdbcTemplate, Serializable id) {
        if (this.jdbcTemplate == null) {
            setJdbcTemplate(jdbcTemplate);
        }
        
        String tableName = EntityTableInfo.getTableName(valueClass);
        Field idField = EntityTableInfo.getIdField(valueClass);
        String idColumnName = EntityTableInfo.getColumnName(idField);
        
        String sql = "SELECT * FROM " + tableName + " WHERE " + idColumnName + " = ?";
        List<E> results = jdbcTemplate.query(sql, new Object[]{id}, rowMapper);
        return results.isEmpty() ? null : results.get(0);
    }

    /**
     * 判断字段是否为关联字段
     */
    private boolean isAssociationField(Field field) {
        return field.isAnnotationPresent(ManyToOne.class) ||
               field.isAnnotationPresent(OneToMany.class) ||
               field.isAnnotationPresent(ManyToMany.class) ||
               field.isAnnotationPresent(OneToOne.class);
    }

    /**
     * 将字段名转换为列名
     */
    private String getColumnNameFromFieldName(String fieldName) {
        // 如果包含点号，说明是关联字段，需要特殊处理
        if (fieldName.contains(".")) {
            // 简化处理：只取最后一部分
            String[] parts = fieldName.split("\\.");
            fieldName = parts[parts.length - 1];
        }
        
        // 尝试从实体类中找到对应的字段
        List<Field> fields = BeanUtils.getFields(valueClass, true);
        for (Field field : fields) {
            if (field.getName().equals(fieldName)) {
                return EntityTableInfo.getColumnName(field);
            }
        }
        
        // 如果找不到，使用驼峰转下划线
        return camelToSnakeCase(fieldName);
    }

    /**
     * 驼峰命名转下划线命名
     */
    private String camelToSnakeCase(String camelCase) {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < camelCase.length(); i++) {
            char c = camelCase.charAt(i);
            if (Character.isUpperCase(c)) {
                if (i > 0) {
                    result.append('_');
                }
                result.append(Character.toLowerCase(c));
            } else {
                result.append(c);
            }
        }
        return result.toString();
    }

    /**
     * 将 HQL 转换为 SQL（简化版本，复杂情况需要手动转换）
     */
    private String convertHqlToSql(String hql) {
        // 简单的 HQL 到 SQL 转换
        // 注意：这是一个简化版本，复杂的 HQL 需要手动转换
        String sql = hql;
        
        // 替换 FROM 子句中的实体类名为表名
        String entityName = valueClass.getSimpleName();
        String tableName = EntityTableInfo.getTableName(valueClass);
        sql = sql.replace("FROM " + entityName, "FROM " + tableName);
        sql = sql.replace("from " + entityName, "FROM " + tableName);
        
        // 替换字段名为列名（简化处理）
        // 注意：复杂的 HQL 需要手动转换
        
        return sql;
    }
}
