package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.ClientType;
import beidanci.api.model.MsgType;
import beidanci.api.model.PagedResults;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.Msg;
import beidanci.service.po.User;
import beidanci.service.socket.SocketService;
import beidanci.service.util.Util;
import beidanci.util.Constants;

@Service
@Transactional(rollbackFor = Throwable.class)
public class MsgBo extends BaseBo<Msg> {
    private static final Logger logger = LoggerFactory.getLogger(MsgBo.class);

    @Autowired
    UserBo userBo;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<Msg>() {
        });
    }

    /**
     * 分页查询发往指定用户的消息
     *
     * @param page
     * @param rows
     * @param toUserId
     * @param msgType
     * @return
     */
    public PagedResults<Msg> getMsgsByPage(int page, int rows, Integer toUserId, MsgType msgType) {
        // 构建 SQL 查询
        StringBuilder sqlBuilder = new StringBuilder(
            "SELECT m.* FROM msg m WHERE m.id = (" +
            "    SELECT MAX(mm.id) FROM msg mm WHERE mm.from_user_id = m.from_user_id"
        );
        MapSqlParameterSource params = new MapSqlParameterSource();
        
        if (toUserId != null) {
            sqlBuilder.append(" AND mm.to_user_id = :toUserId");
            params.addValue("toUserId", toUserId);
        }
        if (msgType != null) {
            sqlBuilder.append(" AND mm.msg_type = :msgType");
            params.addValue("msgType", msgType.toString());
        }
        sqlBuilder.append(") ORDER BY m.update_time DESC");
        
        String sql = sqlBuilder.toString();
        
        // 查询总数
        String countSql = "SELECT COUNT(*) FROM (" + sql + ") AS count_query";
        Long total = namedParameterJdbcTemplate.queryForObject(countSql, params, Long.class);
        
        // 分页查询
        String pagedSql = sql + " LIMIT :limit OFFSET :offset";
        params.addValue("limit", rows);
        params.addValue("offset", (page - 1) * rows);
        List<Msg> msgs = namedParameterJdbcTemplate.query(pagedSql, params, 
            new EntityRowMapper<>(Msg.class));

        // 批量加载完整的 User 对象，填充 fromUser 和 toUser 字段
        loadUsersForMsgs(msgs);

        PagedResults<Msg> pagedResults = new PagedResults<>();
        pagedResults.setTotal(total != null ? total.intValue() : 0);
        pagedResults.setRows(msgs);
        return pagedResults;
    }

    /**
     * 获取两用户之间的最近若干条消息
     *
     * @param user1
     * @param user2
     * @param msgCount
     * @return
     */
    public List<Msg> getLastestMsgsBetweenTwoUsers(String user1, String user2, int msgCount) {
        String sql = "SELECT * FROM msg WHERE " +
                "((from_user_id = :user1Id AND to_user_id = :user2Id) OR (from_user_id = :user2Id AND to_user_id = :user1Id)) " +
                "ORDER BY create_time ASC";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("user1Id", user1);
        params.addValue("user2Id", user2);
        
        // 查询数据总条数
        String countSql = "SELECT COUNT(*) FROM (" + sql + ") AS count_query";
        Long total = namedParameterJdbcTemplate.queryForObject(countSql, params, Long.class);
        int totalInt = total != null ? total.intValue() : 0;
        
        // 分页查询
        String pagedSql = sql + " LIMIT :limit OFFSET :offset";
        params.addValue("limit", msgCount);
        params.addValue("offset", totalInt >= msgCount ? totalInt - msgCount : 0);
        
        List<Msg> msgs = namedParameterJdbcTemplate.query(pagedSql, params, 
            new EntityRowMapper<>(Msg.class));
        
        // 批量加载完整的 User 对象，填充 fromUser 和 toUser 字段
        loadUsersForMsgs(msgs);
        
        return msgs;
    }
    
    /**
     * 批量加载 User 对象并填充到 Msg 的 fromUser 和 toUser 字段
     */
    private void loadUsersForMsgs(List<Msg> msgs) {
        if (msgs == null || msgs.isEmpty()) {
            return;
        }
        
        // 收集所有需要加载的 User ID
        Set<String> userIds = new HashSet<>();
        for (Msg msg : msgs) {
            if (msg.getFromUser() != null && msg.getFromUser().getId() != null) {
                userIds.add(msg.getFromUser().getId());
            }
            if (msg.getToUser() != null && msg.getToUser().getId() != null) {
                userIds.add(msg.getToUser().getId());
            }
        }
        
        if (userIds.isEmpty()) {
            return;
        }
        
        // 批量查询 User 对象
        String sql = "SELECT * FROM \"user\" WHERE id IN (:ids)";
        MapSqlParameterSource params = new MapSqlParameterSource("ids", userIds);
        List<User> users = namedParameterJdbcTemplate.query(sql, params,
            new EntityRowMapper<>(User.class));
        
        // 构建 User ID 到 User 对象的映射
        Map<String, User> userMap = new HashMap<>();
        for (User user : users) {
            userMap.put(user.getId(), user);
        }
        
        // 填充 Msg 的 fromUser 和 toUser 字段
        for (Msg msg : msgs) {
            if (msg.getFromUser() != null && msg.getFromUser().getId() != null) {
                User fullUser = userMap.get(msg.getFromUser().getId());
                if (fullUser != null) {
                    msg.setFromUser(fullUser);
                }
            }
            if (msg.getToUser() != null && msg.getToUser().getId() != null) {
                User fullUser = userMap.get(msg.getToUser().getId());
                if (fullUser != null) {
                    msg.setToUser(fullUser);
                }
            }
        }
    }

    /**
     * 获取用户和系统之间的最近若干条消息
     *
     * @return
     */
    public List<Msg> getLastestMsgsBetweenUserAndSys(String user1, int msgCount, UserBo userBo) {
        User user2_ = userBo.getByUserName(Constants.SYS_USER_SYS, false);

        return getLastestMsgsBetweenTwoUsers(user1, user2_.getId(), msgCount);
    }

    /**
     * 获取发往指定用户的未读持久消息数量
     *
     * @return
     */
    public int getUnViewedPersistentMsgCountToUser(String toUserId) {
        try {
            String sql = "SELECT COUNT(*) FROM msg WHERE to_user_id = :toUserId AND viewed = false";
            MapSqlParameterSource params = new MapSqlParameterSource("toUserId", toUserId);
            Long count = namedParameterJdbcTemplate.queryForObject(sql, params, Long.class);
            // 确保返回非 null 值，避免 JSON 序列化时出现 null
            if (count == null) {
                return 0;
            }
            return count.intValue();
        } catch (EmptyResultDataAccessException e) {
            // COUNT(*) 不应该返回空结果，但为了安全起见处理这种情况
            return 0;
        } catch (Exception e) {
            // 处理任何其他异常，确保始终返回非 null 值
            logger.error("获取未读持久消息数量失败: toUserId={}", toUserId, e);
            return 0;
        }
    }

    /**
     * 获取发往指定用户的所有持久消息数量
     *
     * @return
     */
    public int getAllPersistentMsgCountToUser(String toUserId) {
        try {
            String sql = "SELECT COUNT(*) FROM msg WHERE to_user_id = :toUserId";
            MapSqlParameterSource params = new MapSqlParameterSource("toUserId", toUserId);
            Long count = namedParameterJdbcTemplate.queryForObject(sql, params, Long.class);
            // 确保返回非 null 值，避免 JSON 序列化时出现 null
            if (count == null) {
                return 0;
            }
            return count.intValue();
        } catch (EmptyResultDataAccessException e) {
            // COUNT(*) 不应该返回空结果，但为了安全起见处理这种情况
            return 0;
        } catch (Exception e) {
            // 处理任何其他异常，确保始终返回非 null 值
            logger.error("获取所有持久消息数量失败: toUserId={}", toUserId, e);
            return 0;
        }
    }

    public void sendAdvice(String content, String clientType, User fromUser) {
        createMsg(content, MsgType.Advice, clientType, fromUser, userBo.getSysUser_sys(false));
        Util.sendEmailToNnbdcCustomerSerivce(String.format("来自[%s]的意见", fromUser.getNickName()), content);
    }

    public void replyAdvice(String content, User toUser, UserBo userBo) {
        createMsg(content, MsgType.AdviceReply, userBo.getSysUser_sys(false), toUser);

        // 向用户推送通知，告知最新的消息数量情况
        SocketService.getInstance().sendPersistentMsgCountToUser(userBo.getUserVoById(toUser.getId()));
    }

    public void createMsg(String content, MsgType msgType, String clientType, User fromUser, User toUser) {
        Msg msg = new Msg(msgType);
        msg.setFromUser(fromUser);
        msg.setToUser(toUser);
        msg.setContent(content);
        msg.setViewed(false);
        msg.setCreateTime(new Date());
        
        // 设置客户端类型
        System.out.println("DEBUG: 接收到的clientType参数: " + clientType);
        if (clientType != null && !clientType.trim().isEmpty()) {
            try {
                ClientType clientTypeEnum = ClientType.valueOf(clientType);
                msg.setClientType(clientTypeEnum);
                System.out.println("DEBUG: 成功设置clientType: " + clientTypeEnum);
            } catch (IllegalArgumentException e) {
                // 如果客户端类型无效，设置为null
                System.out.println("DEBUG: clientType无效: " + clientType + ", 错误: " + e.getMessage());
                msg.setClientType(null);
            }
        } else {
            System.out.println("DEBUG: clientType为空或null");
        }
        
        createEntity(msg);
        System.out.println("DEBUG: 消息已保存，clientType: " + msg.getClientType());
    }

    public void createMsg(String content, MsgType msgType, User fromUser, User toUser) {
        createMsg(content, msgType, null, fromUser, toUser);
    }

    /**
     * 把某用户的若干指定消息（发往该用户或该用户发起的消息）置为已读
     *
     * @param msgIds
     */
    public void setMsgsAsViewed(List<String> msgIds, String userId, UserBo userBo) {
        String sql = "UPDATE msg SET viewed = 1 WHERE id IN (:ids) AND (to_user_id = :userId OR from_user_id = :userId)";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("ids", msgIds);
        params.addValue("userId", userId);
        namedParameterJdbcTemplate.update(sql, params);

        // 向用户推送通知，告知最新的消息数量情况
        SocketService.getInstance().sendPersistentMsgCountToUser(userBo.getUserVoById(userId));
    }

    /**
     * 获取所有用户的意见建议消息（管理员功能）
     *
     * @return 意见建议消息列表
     */
    public List<Msg> getAllAdviceMessages() {
        String sql = "SELECT * FROM msg WHERE msg_type = :msgType ORDER BY create_time DESC";
        MapSqlParameterSource params = new MapSqlParameterSource("msgType", MsgType.Advice.toString());
        List<Msg> msgs = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(Msg.class));
        
        // 批量加载完整的 User 对象，填充 fromUser 和 toUser 字段
        loadUsersForMsgs(msgs);
        
        return msgs;
    }
}
