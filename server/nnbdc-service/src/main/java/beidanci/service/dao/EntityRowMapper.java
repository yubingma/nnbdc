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
import javax.persistence.ManyToOne;
import javax.persistence.OneToMany;

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
        
        for (Field field : fields) {
            // 跳过关联字段（ManyToOne, OneToMany 等）
            if (field.isAnnotationPresent(ManyToOne.class) || 
                field.isAnnotationPresent(OneToMany.class)) {
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
            
            for (int i = 1; i <= columnCount; i++) {
                String columnName = metaData.getColumnLabel(i).toLowerCase();
                Field field = columnToFieldMap.get(columnName);
                
                if (field != null) {
                    Object value = rs.getObject(i);
                    if (value != null) {
                        setFieldValue(entity, field, value);
                    }
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
        }
    }
}

