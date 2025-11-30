package beidanci.service.dao;

import java.io.Serializable;
import java.lang.reflect.Field;
import java.lang.reflect.ParameterizedType;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;

import javax.persistence.Column;

import org.apache.commons.lang.StringUtils;
import org.apache.commons.lang3.tuple.Pair;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

import beidanci.api.model.PagedResults;
import beidanci.service.UuidSetter;
import beidanci.service.po.Po;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.ReflectionUtil;


/**
 * DAO基类，支持基本的CRUD、分页、模糊查询 <br>
 * 使用 Spring JDBC + RowMapper 替代 Hibernate
 * 
 * @param <E>
 * @author MaYubing
 */
public abstract class BaseDao<E extends Po> {
    private static final Logger logger = LoggerFactory.getLogger(BaseDao.class);

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
        this.jdbcTemplate = Objects.requireNonNull(jdbcTemplate, "JdbcTemplate cannot be null");
        this.namedParameterJdbcTemplate = new NamedParameterJdbcTemplate(this.jdbcTemplate);
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
        
        // 检查主键是否是复合主键（@Embeddable）
        boolean isCompositeKey = idField.getType().isAnnotationPresent(javax.persistence.Embeddable.class);
        
        // 收集复合主键中的列名（用于避免重复）
        Set<String> compositeKeyColumnNames = new HashSet<>();
        if (isCompositeKey) {
            try {
                idField.setAccessible(true);
                Object compositeKey = idField.get(entity);
                if (compositeKey != null) {
                    List<Field> keyFields = BeanUtils.getFields(compositeKey.getClass(), true);
                    for (Field keyField : keyFields) {
                        String columnName = EntityTableInfo.getColumnName(keyField);
                        compositeKeyColumnNames.add(columnName.toLowerCase());
                    }
                }
            } catch (IllegalAccessException e) {
                logger.error("创建实体时获取复合主键列名失败: entityClass={}", valueClass.getName(), e);
            }
        }
        
        // 构建 INSERT SQL
        StringBuilder sql = new StringBuilder("INSERT INTO ");
        sql.append(tableName).append(" (");
        
        List<Field> fields = BeanUtils.getFields(valueClass, true);
        List<String> columnNames = new ArrayList<>();
        List<Object> values = new ArrayList<>();
        
        for (Field field : fields) {
            // 处理主键字段
            if (field.equals(idField)) {
                // 如果是复合主键，处理其内部字段
                if (isCompositeKey) {
                    try {
                        field.setAccessible(true);
                        Object compositeKey = field.get(entity);
                        if (compositeKey != null) {
                            // 获取复合主键类的所有字段
                            List<Field> keyFields = BeanUtils.getFields(compositeKey.getClass(), true);
                            for (Field keyField : keyFields) {
                                // 跳过 static 和 final 字段（如 serialVersionUID）
                                int modifiers = keyField.getModifiers();
                                if (java.lang.reflect.Modifier.isStatic(modifiers) || 
                                    java.lang.reflect.Modifier.isFinal(modifiers)) {
                                    continue;
                                }
                                
                                // 只处理有 @Column 注解的字段（复合主键的组件字段应该有 @Column 注解）
                                if (!keyField.isAnnotationPresent(Column.class)) {
                                    continue;
                                }
                                
                                keyField.setAccessible(true);
                                Object keyValue = keyField.get(compositeKey);
                                String columnName = EntityTableInfo.getColumnName(keyField);
                                columnNames.add(columnName);
                                values.add(keyValue);
                            }
                        }
                    } catch (IllegalAccessException e) {
                        logger.error("创建实体时获取复合主键字段值失败: entityClass={}, field={}", 
                            valueClass.getName(), field.getName(), e);
                        throw new RuntimeException("获取复合主键字段值失败: " + field.getName(), e);
                    }
                } else {
                    // 简单主键（String/UUID）：UuidSetter 已设置值，需要添加到 INSERT 语句中
                    try {
                        field.setAccessible(true);
                        Object idValue = field.get(entity);
                        String idColumnName = EntityTableInfo.getColumnName(idField);
                        columnNames.add(idColumnName);
                        values.add(idValue);
                    } catch (IllegalAccessException e) {
                        logger.error("创建实体时获取主键字段值失败: entityClass={}, field={}", 
                            valueClass.getName(), field.getName(), e);
                        throw new RuntimeException("获取主键字段值失败: " + field.getName(), e);
                    }
                }
                continue;
            }
            
            // 处理关联对象字段（类型为 Po 的子类，且不是以 "Id" 结尾的字段）
            // 约定：关联对象字段的外键列名为 字段名 + "Id"（如 level -> levelId）
            if (Po.class.isAssignableFrom(field.getType()) && !field.getName().endsWith("Id")) {
                String foreignKeyColumnName = field.getName() + "Id";
                
                // 如果该列名已经在复合主键中，则跳过（避免重复）
                if (isCompositeKey && compositeKeyColumnNames.contains(foreignKeyColumnName.toLowerCase())) {
                    continue;
                }
                
                try {
                    field.setAccessible(true);
                    Object associatedObject = field.get(entity);
                    Object foreignKeyValue = null;
                    
                    if (associatedObject != null) {
                        // 提取关联对象的 ID
                        @SuppressWarnings("unchecked")
                        Class<? extends Po> associatedPoClass = (Class<? extends Po>) field.getType();
                        Field associatedIdField = EntityTableInfo.getIdField(associatedPoClass);
                        associatedIdField.setAccessible(true);
                        foreignKeyValue = associatedIdField.get(associatedObject);
                    }
                    
                    columnNames.add(foreignKeyColumnName);
                    values.add(foreignKeyValue);
                } catch (IllegalAccessException e) {
                    logger.error("创建实体时获取关联字段值失败: entityClass={}, field={}", 
                        valueClass.getName(), field.getName(), e);
                    throw new RuntimeException("获取关联字段值失败: " + field.getName(), e);
                }
                continue;
            }
            
            // 跳过集合类型字段（List, Set 等）- 这些在 JDBC 中不需要
            if (java.util.Collection.class.isAssignableFrom(field.getType())) {
                continue;
            }
            
            // 检查 @Column 注解的 insertable 属性
            if (field.isAnnotationPresent(Column.class)) {
                Column column = field.getAnnotation(Column.class);
                if (!column.insertable()) {
                    continue; // 跳过 insertable = false 的字段
                }
            }
            
            String columnName = EntityTableInfo.getColumnName(field);
            
            // 如果该列名已经在复合主键中，则跳过（避免重复）
            if (isCompositeKey && compositeKeyColumnNames.contains(columnName.toLowerCase())) {
                continue;
            }
            
            columnNames.add(columnName);
            
            try {
                field.setAccessible(true);
                Object value = field.get(entity);
                
                // 处理枚举类型：如果字段是枚举且使用 @Enumerated(EnumType.STRING)，转换为字符串
                if (value != null && field.getType().isEnum()) {
                    if (field.isAnnotationPresent(javax.persistence.Enumerated.class)) {
                        javax.persistence.Enumerated enumerated = field.getAnnotation(javax.persistence.Enumerated.class);
                        if (enumerated.value() == javax.persistence.EnumType.STRING) {
                            value = ((Enum<?>) value).name();
                        }
                    } else {
                        // 如果没有 @Enumerated 注解，默认使用字符串形式
                        value = ((Enum<?>) value).name();
                    }
                }
                
                values.add(value);
            } catch (IllegalAccessException e) {
                logger.error("创建实体时获取字段值失败: entityClass={}, field={}", 
                    valueClass.getName(), field.getName(), e);
                throw new RuntimeException("获取字段值失败: " + field.getName(), e);
            }
        }
        
        sql.append(String.join(", ", columnNames));
        sql.append(") VALUES (");
        sql.append(String.join(", ", columnNames.stream().map(c -> "?").toList()));
        sql.append(")");
        
        String finalSql = Objects.requireNonNull(sql.toString(), "SQL cannot be null");
        jdbcTemplate.update(finalSql, values.toArray());
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
            paramSource.addValue(Objects.requireNonNull(param.getLeft(), "Parameter key cannot be null"), param.getRight());
        }
        
        // 查询总数
        String countSql = "SELECT COUNT(*) FROM (" + Objects.requireNonNull(convertedSql, "SQL cannot be null") + ") AS count_query";
        Integer total = namedParameterJdbcTemplate.queryForObject(countSql, paramSource, Integer.class);
        
        // 分页查询
        String pagedSql = convertedSql + " LIMIT :limit OFFSET :offset";
        paramSource.addValue("limit", pageSize);
        paramSource.addValue("offset", (pageNo - 1) * pageSize);
        
        List<E> rows = namedParameterJdbcTemplate.query(pagedSql, paramSource, Objects.requireNonNull(rowMapper, "RowMapper cannot be null"));
        
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
            paramSource.addValue(Objects.requireNonNull(param.getLeft(), "Parameter key cannot be null"), param.getRight());
        }
        
        List<E> results = namedParameterJdbcTemplate.query(
            Objects.requireNonNull(convertedSql, "SQL cannot be null"), 
            paramSource, 
            Objects.requireNonNull(rowMapper, "RowMapper cannot be null"));
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
            paramSource.addValue(Objects.requireNonNull(param.getLeft(), "Parameter key cannot be null"), param.getRight());
        }
        
        // 查询总数
        String countSql = "SELECT COUNT(*) FROM (" + Objects.requireNonNull(convertedSql, "SQL cannot be null") + ") AS count_query";
        Integer total = namedParameterJdbcTemplate.queryForObject(countSql, paramSource, Integer.class);
        
        // 分页查询
        String pagedSql = convertedSql + " LIMIT :limit OFFSET :offset";
        paramSource.addValue("limit", pageSize);
        paramSource.addValue("offset", fromIndex);
        
        List<E> rows = namedParameterJdbcTemplate.query(pagedSql, paramSource, Objects.requireNonNull(rowMapper, "RowMapper cannot be null"));
        
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
        // int paramIndex = 1; // 未使用
        
        // 添加精确查询条件
        if (preciseEntity != null) {
            List<Field> fields = BeanUtils.getFields(valueClass, true);
            for (Field field : fields) {
                // 跳过集合类型字段和关联对象字段（这些在查询条件中不需要）
                if (java.util.Collection.class.isAssignableFrom(field.getType()) ||
                    (Po.class.isAssignableFrom(field.getType()) && !field.getName().endsWith("Id"))) {
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
        
        // 查询总数 - 转换为命名参数 SQL
        String countSqlStr = sql.toString();
        MapSqlParameterSource countParams = new MapSqlParameterSource();
        StringBuilder countSqlBuilder = new StringBuilder();
        int countParamIndex = 0;
        for (int i = 0; i < countSqlStr.length(); i++) {
            if (countSqlStr.charAt(i) == '?') {
                String paramName = "p" + countParamIndex;
                countSqlBuilder.append(":").append(paramName);
                countParams.addValue(paramName, params.get(countParamIndex));
                countParamIndex++;
            } else {
                countSqlBuilder.append(countSqlStr.charAt(i));
            }
        }
        String countSql = "SELECT COUNT(*) FROM (" + countSqlBuilder.toString() + ") AS count_query";
        Integer total = namedParameterJdbcTemplate.queryForObject(countSql, countParams, Integer.class);
        
        // 分页查询 - 转换为命名参数 SQL
        sql.append(" LIMIT :limit OFFSET :offset");
        String querySqlStr = sql.toString();
        MapSqlParameterSource queryParams = new MapSqlParameterSource();
        StringBuilder querySqlBuilder = new StringBuilder();
        int queryParamIndex = 0;
        for (int i = 0; i < querySqlStr.length(); i++) {
            char c = querySqlStr.charAt(i);
            if (c == '?') {
                String paramName = "p" + queryParamIndex;
                querySqlBuilder.append(":").append(paramName);
                queryParams.addValue(paramName, params.get(queryParamIndex));
                queryParamIndex++;
            } else if (i < querySqlStr.length() - 6 && querySqlStr.substring(i, i + 6).equals(":limit")) {
                querySqlBuilder.append(":limit");
                i += 5; // 跳过 ":limit"
            } else if (i < querySqlStr.length() - 8 && querySqlStr.substring(i, i + 8).equals(":offset")) {
                querySqlBuilder.append(":offset");
                i += 7; // 跳过 ":offset"
            } else {
                querySqlBuilder.append(c);
            }
        }
        queryParams.addValue("limit", pageSize);
        queryParams.addValue("offset", (pageNo - 1) * pageSize);
        
        List<E> rows = namedParameterJdbcTemplate.query(
            Objects.requireNonNull(querySqlBuilder.toString(), "SQL cannot be null"), 
            queryParams, 
            Objects.requireNonNull(rowMapper, "RowMapper cannot be null"));
        
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
                // 跳过集合类型字段和关联对象字段（这些在查询条件中不需要）
                if (java.util.Collection.class.isAssignableFrom(field.getType()) ||
                    (Po.class.isAssignableFrom(field.getType()) && !field.getName().endsWith("Id"))) {
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
        
        // 查询总数 - 转换为命名参数 SQL
        String countSqlStr = sql.toString();
        MapSqlParameterSource countParams = new MapSqlParameterSource();
        StringBuilder countSqlBuilder = new StringBuilder();
        int countParamIndex = 0;
        for (int i = 0; i < countSqlStr.length(); i++) {
            if (countSqlStr.charAt(i) == '?') {
                String paramName = "p" + countParamIndex;
                countSqlBuilder.append(":").append(paramName);
                countParams.addValue(paramName, params.get(countParamIndex));
                countParamIndex++;
            } else {
                countSqlBuilder.append(countSqlStr.charAt(i));
            }
        }
        String countSql = "SELECT COUNT(*) FROM (" + Objects.requireNonNull(countSqlBuilder.toString(), "SQL cannot be null") + ") AS count_query";
        Integer total = namedParameterJdbcTemplate.queryForObject(countSql, countParams, Integer.class);
        
        // 分页查询 - 转换为命名参数 SQL
        sql.append(" LIMIT :limit OFFSET :offset");
        String querySqlStr = sql.toString();
        MapSqlParameterSource queryParams = new MapSqlParameterSource();
        StringBuilder querySqlBuilder = new StringBuilder();
        int queryParamIndex = 0;
        for (int i = 0; i < querySqlStr.length(); i++) {
            char c = querySqlStr.charAt(i);
            if (c == '?') {
                String paramName = "p" + queryParamIndex;
                querySqlBuilder.append(":").append(paramName);
                queryParams.addValue(paramName, params.get(queryParamIndex));
                queryParamIndex++;
            } else if (i < querySqlStr.length() - 6 && querySqlStr.substring(i, i + 6).equals(":limit")) {
                querySqlBuilder.append(":limit");
                i += 5;
            } else if (i < querySqlStr.length() - 8 && querySqlStr.substring(i, i + 8).equals(":offset")) {
                querySqlBuilder.append(":offset");
                i += 7;
            } else {
                querySqlBuilder.append(c);
            }
        }
        queryParams.addValue("limit", pageSize);
        queryParams.addValue("offset", fromIndex);
        
        List<E> rows = namedParameterJdbcTemplate.query(
            Objects.requireNonNull(querySqlBuilder.toString(), "SQL cannot be null"), 
            queryParams, 
            Objects.requireNonNull(rowMapper, "RowMapper cannot be null"));
        
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
            // 跳过主键
            if (field.equals(idField)) {
                continue;
            }
            
            // 处理关联对象字段（类型为 Po 的子类，且不是以 "Id" 结尾的字段）
            // 约定：关联对象字段的外键列名为 字段名 + "Id"（如 level -> levelId）
            if (Po.class.isAssignableFrom(field.getType()) && !field.getName().endsWith("Id")) {
                String foreignKeyColumnName = field.getName() + "Id";
                
                try {
                    field.setAccessible(true);
                    Object associatedObject = field.get(entity);
                    Object foreignKeyValue = null;
                    
                    if (associatedObject != null) {
                        // 提取关联对象的 ID
                        @SuppressWarnings("unchecked")
                        Class<? extends Po> associatedPoClass = (Class<? extends Po>) field.getType();
                        Field associatedIdField = EntityTableInfo.getIdField(associatedPoClass);
                        associatedIdField.setAccessible(true);
                        foreignKeyValue = associatedIdField.get(associatedObject);
                    }
                    
                    setParts.add(foreignKeyColumnName + " = ?");
                    values.add(foreignKeyValue);
                } catch (IllegalAccessException e) {
                    logger.error("更新实体时获取关联字段值失败: entityClass={}, field={}", 
                        valueClass.getName(), field.getName(), e);
                    throw new RuntimeException("获取关联字段值失败: " + field.getName(), e);
                }
                continue;
            }
            
            // 跳过集合类型字段（List, Set 等）- 这些在 JDBC 中不需要
            if (java.util.Collection.class.isAssignableFrom(field.getType())) {
                continue;
            }
            
            String columnName = EntityTableInfo.getColumnName(field);
            setParts.add(columnName + " = ?");
            
            try {
                field.setAccessible(true);
                Object value = field.get(entity);
                
                // 处理枚举类型：如果字段是枚举且使用 @Enumerated(EnumType.STRING)，转换为字符串
                if (value != null && field.getType().isEnum()) {
                    if (field.isAnnotationPresent(javax.persistence.Enumerated.class)) {
                        javax.persistence.Enumerated enumerated = field.getAnnotation(javax.persistence.Enumerated.class);
                        if (enumerated.value() == javax.persistence.EnumType.STRING) {
                            value = ((Enum<?>) value).name();
                        }
                    } else {
                        // 如果没有 @Enumerated 注解，默认使用字符串形式
                        value = ((Enum<?>) value).name();
                    }
                }
                
                values.add(value);
            } catch (IllegalAccessException e) {
                logger.error("更新实体时获取字段值失败: entityClass={}, field={}", 
                    valueClass.getName(), field.getName(), e);
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
            logger.error("更新实体时获取主键值失败: entityClass={}", valueClass.getName(), e);
            throw new RuntimeException("获取主键值失败", e);
        }
        
        jdbcTemplate.update(Objects.requireNonNull(sql.toString(), "SQL cannot be null"), values.toArray());
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
            logger.error("删除实体时获取主键值失败: entityClass={}", valueClass.getName(), e);
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
        
        // 检查主键是否是复合主键（@Embeddable）
        boolean isCompositeKey = idField.getType().isAnnotationPresent(javax.persistence.Embeddable.class);
        
        String sql;
        MapSqlParameterSource params = new MapSqlParameterSource();
        
        if (isCompositeKey) {
            // 复合主键：需要根据所有组件字段构建 WHERE 条件
            try {
                Object compositeKey = id;
                if (compositeKey == null) {
                    throw new IllegalArgumentException("复合主键不能为 null");
                }
                
                List<Field> keyFields = BeanUtils.getFields(compositeKey.getClass(), true);
                StringBuilder whereClause = new StringBuilder();
                boolean first = true;
                
                for (Field keyField : keyFields) {
                    // 跳过 static 和 final 字段（如 serialVersionUID）
                    int modifiers = keyField.getModifiers();
                    if (java.lang.reflect.Modifier.isStatic(modifiers) || 
                        java.lang.reflect.Modifier.isFinal(modifiers)) {
                        continue;
                    }
                    
                    // 只处理有 @Column 注解的字段（复合主键的组件字段应该有 @Column 注解）
                    if (!keyField.isAnnotationPresent(Column.class)) {
                        continue;
                    }
                    
                    keyField.setAccessible(true);
                    Object keyValue = keyField.get(compositeKey);
                    String columnName = Objects.requireNonNull(EntityTableInfo.getColumnName(keyField));
                    
                    if (!first) {
                        whereClause.append(" AND ");
                    }
                    whereClause.append(columnName).append(" = :").append(columnName);
                    params.addValue(columnName, keyValue);
                    first = false;
                }
                
                sql = "SELECT * FROM " + tableName + " WHERE " + Objects.requireNonNull(whereClause.toString());
            } catch (IllegalAccessException e) {
                logger.error("根据复合主键查询实体时获取主键字段值失败: entityClass={}", valueClass.getName(), e);
                throw new RuntimeException("获取复合主键字段值失败", e);
            }
        } else {
            // 简单主键
            String idColumnName = EntityTableInfo.getColumnName(idField);
            sql = "SELECT * FROM " + tableName + " WHERE " + idColumnName + " = :id";
            params.addValue("id", id);
        }
        
        List<E> results = namedParameterJdbcTemplate.query(
            Objects.requireNonNull(sql, "SQL cannot be null"), 
            params, 
            Objects.requireNonNull(rowMapper, "RowMapper cannot be null"));
        return results.isEmpty() ? null : results.get(0);
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
        
        // 如果找不到，直接使用字段名（驼峰格式）
        return fieldName;
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
