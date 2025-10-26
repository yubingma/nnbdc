package beidanci.service.dao;

import java.util.List;
import java.util.Optional;

import javax.annotation.Resource;

import org.hibernate.Session;
import org.hibernate.SessionFactory;
import org.hibernate.query.Query;
import org.springframework.stereotype.Repository;

import beidanci.service.po.User;
import beidanci.service.po.UserDbVersion;
import beidanci.service.util.Util;
import beidanci.util.Constants;

@Repository
public class UserDbVersionDao extends BaseDao<UserDbVersion> {
    
    @Resource(name = "sessionFactory")
    private SessionFactory sessionFactory;
    
    public Session getSession() {
        return sessionFactory.getCurrentSession();
    }

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
     * @param session Hibernate会话
     * @param userId  用户ID
     * @return 数据库版本号，若不存在则返回初始版本
     * @see #getUserDbVersionWithLock(Session, String) 带锁的查询方法，用于事务中的修改操作
     */
    public int getUserDbVersion(Session session, String userId) {
        String hql = "FROM UserDbVersion WHERE user.id = :userId";
        UserDbVersion userDbVersion = (UserDbVersion) session.createQuery(hql)
                .setParameter("userId", userId)
                .uniqueResult();
        return Optional.ofNullable(userDbVersion)
                .map(UserDbVersion::getVersion)
                .orElse(Constants.USER_DB_VERSION_INITIAL);
    }

    /**
     * 获取用户数据库版本（使用 FOR UPDATE 行锁，防止并发冲突）
     * 
     * 注意：此方法会对版本号记录加排他锁，直到事务提交或回滚才会释放
     * 这样可以确保同一时刻只有一个事务能够修改该用户的数据库版本
     *
     * @param session Hibernate会话
     * @param userId  用户ID
     * @return 数据库版本号，若不存在则返回0
     */
    public int getUserDbVersionWithLock(Session session, String userId) {
        // 使用原生SQL的 FOR UPDATE 子句来加行锁
        String sql = "SELECT version FROM user_db_version WHERE userId = :userId FOR UPDATE";
        Integer version = (Integer) session.createNativeQuery(sql)
                .setParameter("userId", userId)
                .uniqueResult();
        
        return version != null ? version : Constants.USER_DB_VERSION_INITIAL;
    }

    /**
     * 使用 CAS (Compare-And-Swap) 原子更新用户数据库版本
     * 
     * 此方法使用数据库级别的原子操作来更新版本号，只有当当前版本号等于期望值时才会更新
     * 这样可以防止并发更新导致的版本号覆盖问题
     *
     * @param session         Hibernate会话
     * @param userId          用户ID
     * @param expectedVersion 期望的当前版本号
     * @param newVersion      新的版本号
     * @return true 表示更新成功，false 表示版本号不匹配更新失败
     */
    public boolean updateUserDbVersionCAS(Session session, String userId, 
                                          int expectedVersion, int newVersion) {
        // 使用 WHERE 条件中的版本号检查来实现 CAS 语义
        String sql = "UPDATE user_db_version SET version = :newVersion " +
                     "WHERE userId = :userId AND version = :expectedVersion";
        int updatedRows = session.createNativeQuery(sql)
                .setParameter("newVersion", newVersion)
                .setParameter("userId", userId)
                .setParameter("expectedVersion", expectedVersion)
                .executeUpdate();
        
        return updatedRows > 0;
    }

    /**
     * 确保用户数据库版本记录存在（如果不存在则创建初始记录）
     * 
     * @param session Hibernate会话
     * @param userId  用户ID
     */
    public void ensureUserDbVersionExists(Session session, String userId) {
        User user = session.get(User.class, userId);
        if (user != null) {
            String hql = "FROM UserDbVersion WHERE user.id = :userId";
            UserDbVersion userDbVersion = (UserDbVersion) session.createQuery(hql)
                    .setParameter("userId", userId)
                    .uniqueResult();
            
            if (userDbVersion == null) {
                // 创建初始版本记录
                userDbVersion = new UserDbVersion(user, Constants.USER_DB_VERSION_INITIAL);
                userDbVersion.setId(Util.uuid());
                session.save(userDbVersion);
                // 立即刷新到数据库，确保后续的原生SQL能看到这条记录
                session.flush();
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
        String sql = """
            SELECT udv.userId, udv.version
            FROM user_db_version udv
            ORDER BY udv.version DESC
            """;
        Query<Object[]> query = getSession().createNativeQuery(sql, Object[].class);
        return query.list();
    }

    /**
     * 统计用户异常日志数量
     */
    public Integer countInvalidLogs(String userId, Integer currentVersion) {
        String hql = "SELECT COUNT(*) FROM UserDbLog udl WHERE udl.user.id = :userId AND udl.version > :currentVersion";
        Query<Long> query = getSession().createQuery(hql, Long.class);
        query.setParameter("userId", userId);
        query.setParameter("currentVersion", currentVersion);
        return query.uniqueResult().intValue();
    }

    /**
     * 删除异常日志
     */
    public void deleteInvalidLogs(String userId, Integer currentVersion) {
        String hql = "DELETE FROM UserDbLog udl WHERE udl.user.id = :userId AND udl.version > :currentVersion";
        Query<?> query = getSession().createQuery(hql);
        query.setParameter("userId", userId);
        query.setParameter("currentVersion", currentVersion);
        query.executeUpdate();
    }
}
