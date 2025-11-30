package beidanci.service.dao;

import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.Map;

import javax.persistence.Column;
import javax.persistence.Id;
import javax.persistence.Table;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import beidanci.service.po.Po;
import beidanci.service.util.BeanUtils;

/**
 * 实体表信息工具类，用于获取表名、主键等信息
 */
public class EntityTableInfo {
    private static final Logger logger = LoggerFactory.getLogger(EntityTableInfo.class);
    private static final Map<Class<?>, String> tableNameCache = new HashMap<>();
    private static final Map<Class<?>, Field> idFieldCache = new HashMap<>();
    
    /**
     * 获取实体类对应的表名
     */
    public static String getTableName(Class<? extends Po> entityClass) {
        String cached = tableNameCache.get(entityClass);
        if (cached != null) {
            return cached;
        }
        
        // 检查 @Table 注解
        if (entityClass.isAnnotationPresent(Table.class)) {
            Table table = entityClass.getAnnotation(Table.class);
            String name = table.name();
            if (!name.isEmpty()) {
                tableNameCache.put(entityClass, name);
                return name;
            }
        }
        
        // 如果没有 @Table 注解，直接使用类名（驼峰格式）
        String tableName = entityClass.getSimpleName();
        tableNameCache.put(entityClass, tableName);
        return tableName;
    }
    
    /**
     * 获取主键字段
     */
    public static Field getIdField(Class<? extends Po> entityClass) {
        Field cached = idFieldCache.get(entityClass);
        if (cached != null) {
            return cached;
        }
        
        java.util.List<Field> fields = BeanUtils.getFields(entityClass, true);
        for (Field field : fields) {
            if (field.isAnnotationPresent(Id.class)) {
                idFieldCache.put(entityClass, field);
                return field;
            }
        }
        
        logger.error("实体类没有找到主键字段: entityClass={}", entityClass.getName());
        throw new RuntimeException("实体类 " + entityClass.getName() + " 没有找到主键字段");
    }
    
    /**
     * 获取字段对应的数据库列名
     */
    public static String getColumnName(Field field) {
        // 优先使用 @Column 注解
        if (field.isAnnotationPresent(Column.class)) {
            Column column = field.getAnnotation(Column.class);
            String name = column.name();
            if (!name.isEmpty()) {
                return name;
            }
        }
        
        // 如果没有 @Column，直接使用字段名（驼峰格式）
        return field.getName();
    }
}

