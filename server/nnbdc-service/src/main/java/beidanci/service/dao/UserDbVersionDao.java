package beidanci.service.dao;

import java.util.List;

import javax.annotation.Resource;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

import beidanci.service.po.UserDbVersion;
import beidanci.service.util.Util;
import beidanci.util.Constants;

@Repository
public class UserDbVersionDao extends BaseDao<UserDbVersion> {
    
    @Resource
    private JdbcTemplate jdbcTemplate;
    
    @Resource
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    /**
     * 获取用户数据库版本（不加锁，仅用于只读查询）
     * 
     * 注意：此方法不加锁，仅适用于纯读取场景，例如：
     * - 前端通过 HTTP 接口查询当前版本号
     * - 生成数据库日志时获取版本号
     * - 其他不涉及写操作的只读场景
     * 
     * 如果需要在事务中修改数据（如数据同步），请使用 getUserDbVersionWithLock 方法加锁
     *
     * @param jdbcTemplate JdbcTemplate
     * @param userId  用户ID
     * @return 数据库版本号，若不存在则返回初始版本
     * @see #getUserDbVersionWithLock(JdbcTemplate, String) 带锁的查询方法，用于事务中的修改操作
     */
    public int getUserDbVersion(JdbcTemplate jdbcTemplate, String userId) {
        String sql = "SELECT version FROM user_db_version WHERE userId = ?";
        List<Integer> results = jdbcTemplate.query(sql, 
            new Object[]{userId}, 
            (rs, rowNum) -> rs.getInt("version"));
        
        return results.isEmpty() ? Constants.USER_DB_VERSION_INITIAL : results.get(0);
    }

    /**
     * 获取用户数据库版本（使用 FOR UPDATE 行锁，防止并发冲突）
     * 
     * 注意：此方法会对版本号记录加排他锁，直到事务提交或回滚才会释放
     * 这样可以确保同一时刻只有一个事务能够修改该用户的数据库版本
     *
     * @param jdbcTemplate JdbcTemplate
     * @param userId  用户ID
     * @return 数据库版本号，若不存在则返回0
     */
    public int getUserDbVersionWithLock(JdbcTemplate jdbcTemplate, String userId) {
        // 使用原生SQL的 FOR UPDATE 子句来加行锁
        String sql = "SELECT version FROM user_db_version WHERE userId = ? FOR UPDATE";
        List<Integer> results = jdbcTemplate.query(sql, 
            new Object[]{userId}, 
            (rs, rowNum) -> rs.getInt("version"));
        
        return results.isEmpty() ? Constants.USER_DB_VERSION_INITIAL : results.get(0);
    }

    /**
     * 使用 CAS (Compare-And-Swap) 原子更新用户数据库版本
     * 
     * 此方法使用数据库级别的原子操作来更新版本号，只有当当前版本号等于期望值时才会更新
     * 这样可以防止并发更新导致的版本号覆盖问题
     *
     * @param jdbcTemplate JdbcTemplate
     * @param userId          用户ID
     * @param expectedVersion 期望的当前版本号
     * @param newVersion      新的版本号
     * @return true 表示更新成功，false 表示版本号不匹配更新失败
     */
    public boolean updateUserDbVersionCAS(JdbcTemplate jdbcTemplate, String userId, 
                                          int expectedVersion, int newVersion) {
        // 使用 WHERE 条件中的版本号检查来实现 CAS 语义
        String sql = "UPDATE user_db_version SET version = ? " +
                     "WHERE userId = ? AND version = ?";
        int updatedRows = jdbcTemplate.update(sql, newVersion, userId, expectedVersion);
        
        return updatedRows > 0;
    }

    /**
     * 确保用户数据库版本记录存在（如果不存在则创建初始记录）
     * 
     * @param jdbcTemplate JdbcTemplate
     * @param userId  用户ID
     */
    public void ensureUserDbVersionExists(JdbcTemplate jdbcTemplate, String userId) {
        // 检查用户是否存在
        String checkUserSql = "SELECT COUNT(*) FROM user WHERE id = ?";
        Integer userCount = jdbcTemplate.queryForObject(checkUserSql, new Object[]{userId}, Integer.class);
        
        if (userCount != null && userCount > 0) {
            // 检查版本记录是否存在
            String checkVersionSql = "SELECT COUNT(*) FROM user_db_version WHERE userId = ?";
            Integer versionCount = jdbcTemplate.queryForObject(checkVersionSql, new Object[]{userId}, Integer.class);
            
            if (versionCount == null || versionCount == 0) {
                // 创建初始版本记录
                String insertSql = "INSERT INTO user_db_version (id, userId, version, createTime, updateTime) VALUES (?, ?, ?, NOW(), NOW())";
                String id = Util.uuid();
                jdbcTemplate.update(insertSql, id, userId, Constants.USER_DB_VERSION_INITIAL);
            }
        }
    }

    // ============================================
    // 系统健康检查相关方法
    // ============================================

    /**
     * 获取所有用户的当前数据库版本
     */
    public List<Object[]> getAllUserVersions() {
        String sql = "SELECT udv.userId, udv.version FROM user_db_version udv ORDER BY udv.version DESC";
        return jdbcTemplate.query(sql, (rs, rowNum) -> new Object[]{
            rs.getString("userId"),
            rs.getInt("version")
        });
    }

    /**
     * 统计用户异常日志数量
     */
    public Integer countInvalidLogs(String userId, Integer currentVersion) {
        String sql = "SELECT COUNT(*) FROM user_db_log WHERE userId = ? AND version > ?";
        return jdbcTemplate.queryForObject(sql, new Object[]{userId, currentVersion}, Integer.class);
    }

    /**
     * 删除异常日志
     */
    public void deleteInvalidLogs(String userId, Integer currentVersion) {
        String sql = "DELETE FROM user_db_log WHERE userId = ? AND version > ?";
        jdbcTemplate.update(sql, userId, currentVersion);
    }
}
