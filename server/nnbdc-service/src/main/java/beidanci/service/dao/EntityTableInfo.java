package beidanci.service.dao;

import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.List;
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
     * 严格校验：列名必须是 snake_case（小写 + 下划线）
     */
    private static void assertSnakeCase(String name, String context) {
        if (name == null || name.trim().isEmpty()) {
            throw new IllegalArgumentException("列名不能为空: " + context);
        }
        String s = name.trim();
        // 允许 a-z0-9_，必须全小写，且不能以下划线开头/结尾
        if (!s.matches("^[a-z0-9]+(?:_[a-z0-9]+)*$")) {
            throw new IllegalArgumentException("列名必须严格为 snake_case（小写+下划线）: name=" + s + ", context=" + context);
        }
    }
    
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
        
        List<Field> fields = BeanUtils.getFields(entityClass, true);
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
     * 获取字段“原始”的数据库列名（未做 snake_case 转换）
     */
    public static String getRawColumnName(Field field) {
        // 优先使用 @Column 注解
        if (field.isAnnotationPresent(Column.class)) {
            Column column = field.getAnnotation(Column.class);
            String name = column.name();
            if (!name.isEmpty()) {
                return name;
            }
        }
        
        // 如果没有 @Column，直接使用字段名（通常为驼峰格式）
        return field.getName();
    }

    /**
     * 获取字段对应的数据库列名（严格 snake_case）
     */
    public static String getColumnName(Field field) {
        String raw = getRawColumnName(field);
        assertSnakeCase(raw, field.getDeclaringClass().getName() + "#" + field.getName());
        return raw.trim();
    }

    /**
     * 获取关联对象字段的外键列名（严格 snake_case）
     * <p>
     * 严格模式下：必须显式使用 @Column(name="...") 指定外键列名，否则立即报错。
     */
    public static String getForeignKeyColumnName(Field field) {
        if (field.isAnnotationPresent(Column.class)) {
            Column column = field.getAnnotation(Column.class);
            String columnName = column.name();
            if (columnName != null && !columnName.isEmpty()) {
                assertSnakeCase(columnName, field.getDeclaringClass().getName() + "#" + field.getName());
                return columnName.trim();
            }
        }
        throw new IllegalArgumentException(
                "严格 snake_case 模式下，关联对象字段必须显式声明 @Column(name=\"...\")："
                        + field.getDeclaringClass().getName() + "#" + field.getName());
    }
}

