package beidanci.service.dao;

import java.lang.reflect.Field;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

import javax.persistence.Column;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.RowMapper;

import beidanci.service.po.Po;
import beidanci.service.util.BeanUtils;

/**
 * 通用的 RowMapper，用于将 ResultSet 映射到 PO 对象
 * 支持通过 @Column 注解指定列名，如果没有注解则使用字段名（驼峰转下划线）
 * 
 * @param <E> PO 类型
 */
public class EntityRowMapper<E extends Po> implements RowMapper<E> {
    private static final Logger logger = LoggerFactory.getLogger(EntityRowMapper.class);
    
    private final Class<E> entityClass;
    private final Map<String, Field> columnToFieldMap;
    
    public EntityRowMapper(Class<E> entityClass) {
        this.entityClass = entityClass;
        this.columnToFieldMap = buildColumnToFieldMap(entityClass);
    }
    
    /**
     * 构建列名到字段的映射
     */
    private Map<String, Field> buildColumnToFieldMap(Class<E> entityClass) {
        Map<String, Field> map = new HashMap<>();
        
        // 获取所有字段（包括父类）
        java.util.List<Field> fields = BeanUtils.getFields(entityClass, true);
        
        // 查找复合主键字段（@Id 且类型是 @Embeddable）
        Field compositeKeyField = null;
        for (Field field : fields) {
            if (field.isAnnotationPresent(javax.persistence.Id.class) && 
                field.getType().isAnnotationPresent(javax.persistence.Embeddable.class)) {
                compositeKeyField = field;
                break;
            }
        }
        
        for (Field field : fields) {
            // 跳过集合类型字段（List, Set 等）- 这些在 JDBC 中不需要
            if (java.util.Collection.class.isAssignableFrom(field.getType())) {
                continue;
            }
            
            // 跳过关联对象字段（类型为 Po 的子类，且不是以 "Id" 结尾的字段）
            // 这些字段对应的外键列会在 ResultSet 中，但我们需要映射到外键列名（字段名 + "Id"）
            if (beidanci.service.po.Po.class.isAssignableFrom(field.getType()) && !field.getName().endsWith("Id")) {
                // 关联对象字段：映射外键列名（字段名 + "Id"）到字段
                String foreignKeyColumnName = field.getName() + "Id";
                map.put(foreignKeyColumnName.toLowerCase(), field);
                continue;
            }
            
            // 如果是复合主键字段本身，跳过（其组件字段会在下面处理）
            if (field.equals(compositeKeyField)) {
                // 处理复合主键的组件字段：将它们映射到复合主键字段
                try {
                    field.setAccessible(true);
                    Class<?> compositeKeyType = field.getType();
                    java.util.List<Field> keyFields = BeanUtils.getFields(compositeKeyType, true);
                    for (Field keyField : keyFields) {
                        String columnName = EntityTableInfo.getColumnName(keyField);
                        // 将复合主键的组件列映射到复合主键字段
                        map.put(columnName.toLowerCase(), field);
                    }
                } catch (Exception e) {
                    logger.error("构建复合主键字段映射时出错: field={}", field.getName(), e);
                }
                continue;
            }
            
            String columnName = getColumnName(field);
            map.put(columnName.toLowerCase(), field);
        }
        
        return map;
    }
    
    /**
     * 获取字段对应的数据库列名
     */
    private String getColumnName(Field field) {
        // 优先使用 @Column 注解
        if (field.isAnnotationPresent(Column.class)) {
            Column column = field.getAnnotation(Column.class);
            String name = column.name();
            if (!name.isEmpty()) {
                return name;
            }
        }
        
        // 如果没有 @Column，使用字段名（驼峰转下划线）
        return camelToSnakeCase(field.getName());
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
    
    @Override
    public E mapRow(@org.springframework.lang.NonNull ResultSet rs, int rowNum) throws SQLException {
        try {
            E entity = entityClass.getDeclaredConstructor().newInstance();
            ResultSetMetaData metaData = rs.getMetaData();
            int columnCount = metaData.getColumnCount();
            
            // 查找复合主键字段（@Id 且类型是 @Embeddable）
            Field compositeKeyField = null;
            java.util.List<Field> fields = BeanUtils.getFields(entityClass, true);
            for (Field field : fields) {
                if (field.isAnnotationPresent(javax.persistence.Id.class) && 
                    field.getType().isAnnotationPresent(javax.persistence.Embeddable.class)) {
                    compositeKeyField = field;
                    break;
                }
            }
            
            // 如果存在复合主键，收集其组件列的值
            Map<String, Object> compositeKeyValues = new HashMap<>();
            if (compositeKeyField != null) {
                Class<?> compositeKeyType = compositeKeyField.getType();
                java.util.List<Field> keyFields = BeanUtils.getFields(compositeKeyType, true);
                for (Field keyField : keyFields) {
                    String columnName = EntityTableInfo.getColumnName(keyField);
                    compositeKeyValues.put(columnName.toLowerCase(), null);
                }
            }
            
            for (int i = 1; i <= columnCount; i++) {
                String columnName = metaData.getColumnLabel(i).toLowerCase();
                Field field = columnToFieldMap.get(columnName);
                
                if (field != null) {
                    Object value = rs.getObject(i);
                    
                    // 如果这个列属于复合主键的组件，收集值而不是直接设置
                    if (compositeKeyField != null && field.equals(compositeKeyField)) {
                        compositeKeyValues.put(columnName, value);
                    } else if (value != null) {
                        setFieldValue(entity, field, value);
                    }
                }
            }
            
            // 如果存在复合主键，创建并设置复合主键对象
            if (compositeKeyField != null && !compositeKeyValues.isEmpty()) {
                try {
                    compositeKeyField.setAccessible(true);
                    Class<?> compositeKeyType = compositeKeyField.getType();
                    Object compositeKey = compositeKeyType.getDeclaredConstructor().newInstance();
                    
                    java.util.List<Field> keyFields = BeanUtils.getFields(compositeKeyType, true);
                    for (Field keyField : keyFields) {
                        String columnName = EntityTableInfo.getColumnName(keyField);
                        Object keyValue = compositeKeyValues.get(columnName.toLowerCase());
                        if (keyValue != null) {
                            keyField.setAccessible(true);
                            // 处理枚举类型
                            if (keyField.getType().isEnum() && keyValue instanceof String) {
                                @SuppressWarnings("unchecked")
                                Class<? extends Enum<?>> enumClass = (Class<? extends Enum<?>>) keyField.getType();
                                java.lang.reflect.Method valueOfMethod = enumClass.getMethod("valueOf", String.class);
                                Enum<?> enumValue = (Enum<?>) valueOfMethod.invoke(null, (String) keyValue);
                                keyField.set(compositeKey, enumValue);
                            } else {
                                keyField.set(compositeKey, keyValue);
                            }
                        }
                    }
                    
                    compositeKeyField.set(entity, compositeKey);
                } catch (Exception e) {
                    logger.error("设置复合主键时出错: entityClass={}, field={}", entityClass.getName(), compositeKeyField.getName(), e);
                    throw new RuntimeException("设置复合主键失败", e);
                }
            }
            
            return entity;
        } catch (Exception e) {
            logger.error("映射 ResultSet 到 {} 时出错", entityClass.getName(), e);
            throw new SQLException("映射 ResultSet 时出错", e);
        }
    }
    
    /**
     * 设置字段值
     */
    private void setFieldValue(E entity, Field field, Object value) {
        try {
            field.setAccessible(true);
            Class<?> fieldType = field.getType();
            
            // 处理关联对象字段：从外键 ID 创建关联对象
            if (Po.class.isAssignableFrom(fieldType) && !field.getName().endsWith("Id")) {
                if (value != null) {
                    // 创建关联对象并设置 ID
                    @SuppressWarnings("unchecked")
                    Class<? extends Po> poClass = (Class<? extends Po>) fieldType;
                    Po associatedObject = poClass.getDeclaredConstructor().newInstance();
                    // 通过反射设置 ID 字段
                    Field idField = beidanci.service.dao.EntityTableInfo.getIdField(poClass);
                    idField.setAccessible(true);
                    idField.set(associatedObject, value);
                    field.set(entity, associatedObject);
                }
                return;
            }
            
            // 处理 Date 类型
            if (fieldType == Date.class && value instanceof Timestamp) {
                field.set(entity, new Date(((Timestamp) value).getTime()));
            } else if (fieldType == Date.class && value instanceof java.sql.Date) {
                field.set(entity, new Date(((java.sql.Date) value).getTime()));
            } 
            // 处理枚举类型：如果字段是枚举类型，且值是字符串，则转换为枚举
            else if (fieldType.isEnum() && value instanceof String) {
                @SuppressWarnings("unchecked")
                Class<? extends Enum<?>> enumClass = (Class<? extends Enum<?>>) fieldType;
                // 使用反射调用 valueOf 方法，因为 Enum.valueOf 需要具体的泛型类型
                try {
                    java.lang.reflect.Method valueOfMethod = enumClass.getMethod("valueOf", String.class);
                    Enum<?> enumValue = (Enum<?>) valueOfMethod.invoke(null, (String) value);
                    field.set(entity, enumValue);
                } catch (NoSuchMethodException | java.lang.reflect.InvocationTargetException e) {
                    logger.error("无法将值转换为枚举类型: field={}, value={}, enumType={}", 
                        field.getName(), value, fieldType.getName(), e);
                    throw new RuntimeException("无法将值 '" + value + "' 转换为枚举类型 " + fieldType.getName(), e);
                }
            } else {
                field.set(entity, value);
            }
        } catch (IllegalAccessException e) {
            logger.error("设置字段值时出错: field={}, value={}", field.getName(), value, e);
        } catch (IllegalArgumentException e) {
            Class<?> fieldType = field.getType();
            logger.error("设置枚举字段值时出错: field={}, value={}, enumType={}", 
                field.getName(), value, fieldType.getName(), e);
            throw new RuntimeException("无法将值 '" + value + "' 转换为枚举类型 " + fieldType.getName(), e);
        } catch (Exception e) {
            logger.error("设置关联对象字段值时出错: field={}, value={}", field.getName(), value, e);
            throw new RuntimeException("设置关联对象字段值失败: " + field.getName(), e);
        }
    }
}

