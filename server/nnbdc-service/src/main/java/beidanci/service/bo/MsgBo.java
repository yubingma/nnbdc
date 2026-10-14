package beidanci.service.bo;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import javax.annotation.PostConstruct;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import beidanci.api.model.AdviceRequirementVo;
import beidanci.api.model.AdviceSessionVo;
import beidanci.api.model.ClientType;
import beidanci.api.model.MsgType;
import beidanci.api.model.MsgVo;
import beidanci.api.model.PagedResults;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.Msg;
import beidanci.service.po.PromoActivity;
import beidanci.service.po.User;
import beidanci.service.socket.SocketService;
import beidanci.service.util.Util;
import beidanci.util.Constants;

@Service
@Transactional(rollbackFor = Throwable.class)
public class MsgBo extends BaseBo<Msg> {
    private static final Logger logger = LoggerFactory.getLogger(MsgBo.class);

    /**
     * 消息正文里标记图片名列表的分隔标记，格式：换行 + 该标记 + JSON 数组，例如
     * 【报错图片】["advice/xxx.jpg"]。单词报错与客服会话共用同一种写法。
     */
    public static final String IMAGE_FILES_MARKER = "【报错图片】";

    /** 消息级需求的标签值 */
    public static final String REQUIREMENT_TAG = "需求";

    @Autowired
    UserBo userBo;

    @Autowired
    private PromoActivityBo promoActivityBo;

    @Autowired
    private PromoRedemptionBo promoRedemptionBo;

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
        } catch (DataAccessException e) {
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
        } catch (DataAccessException e) {
            // 处理任何其他异常，确保始终返回非 null 值
            logger.error("获取所有持久消息数量失败: toUserId={}", toUserId, e);
            return 0;
        }
    }

    public User sendAdvice(String content, String clientType, User fromUser) {
        return sendAdvice(content, clientType, fromUser, null);
    }

    /**
     * 收下用户的一条意见建议。用户可以随消息附上截图，图片由客户端先调 uploadImg.do 上传，
     * 这里只收图片名列表（形如 ["advice/xxx.jpg"]）。
     */
    public User sendAdvice(String content, String clientType, User fromUser, String imageFiles) {
        String storedContent = appendImageFiles(content, imageFiles);
        PromoActivity activity = (promoActivityBo != null && content != null && !content.trim().isEmpty())
                ? promoActivityBo.findMatchingActivityInContent(content)
                : null;

        if (activity != null) {
            // 用户输入了活动兑换码，记录意见建议
            createMsg(storedContent, MsgType.Advice, clientType, fromUser, userBo.getSysUser_sys(false));

            String replyMsg;
            Date now = new Date();
            User updatedUser = null;
            if (!Boolean.TRUE.equals(activity.getIsActive())) {
                replyMsg = "该活动码已下线或暂未启用。";
            } else if (activity.getStartTime() != null && activity.getStartTime().after(now)) {
                replyMsg = "该活动尚未开始。";
            } else if (activity.getEndTime() != null && activity.getEndTime().before(now)) {
                replyMsg = "该活动已结束。";
            } else if (activity.getMaxRedemptions() != null && activity.getMaxRedemptions() > 0
                    && activity.getRedemptionCount() >= activity.getMaxRedemptions()) {
                replyMsg = "该活动码兑换次数已达上限。";
            } else if (promoRedemptionBo.hasRedeemed(fromUser.getId(), activity.getId())) {
                replyMsg = "您已兑换过该活动码，不能重复兑换。";
            } else {
                try {
                    updatedUser = promoRedemptionBo.redeem(fromUser, activity);
                    String durationStr = (activity.getDuration() != null && !activity.getDuration().trim().isEmpty())
                            ? activity.getDuration().trim()
                            : "永久";
                    String replyTemplate = activity.getReplyMessage();
                    if (replyTemplate != null && !replyTemplate.trim().isEmpty()) {
                        replyMsg = replyTemplate
                                .replace("{name}", activity.getName() == null ? "" : activity.getName())
                                .replace("{duration}", durationStr == null ? "" : durationStr);
                    } else {
                        replyMsg = String.format(
                                "【%s】的授权码激活成功！送你的【%s】会员已到账啦 (≧▽≦)\n\n"
                                        + "我们是一个刚刚起步的小团队，这个 App 就像我们的孩子一样。实不相瞒，"
                                        + "我们特别害怕做得不够好让你失望。下个月我们计划上线全新功能，"
                                        + "一定会把它变得越来越好用！如果觉得好用，求求点个赞支持一下 (๑•́ω•̀๑)；"
                                        + "要是遇到不好用的地方，随时在这里吐槽，千万别悄悄删掉我们，给我们一个修正的机会好不好？",
                                activity.getName(), durationStr);
                    }
                } catch (Exception e) {
                    logger.error("意见建议兑换会员失败: userId={}, activityCode={}", fromUser.getId(), activity.getActivityCode(), e);
                    replyMsg = "兑换失败，请稍后重试。";
                }
            }

            // 兑换码的自动回复是针对用户刚发的那句话，不是针对某条历史消息，因此不带引用
            replyAdvice(replyMsg, fromUser, userBo, null, null);
            // 命中兑换码不发送邮件给客服，避免干扰
            return updatedUser;
        }

        createMsg(storedContent, MsgType.Advice, clientType, fromUser, userBo.getSysUser_sys(false));
        Util.sendEmailToNnbdcCustomerSerivce(String.format("来自[%s]的意见", fromUser.getNickName()), storedContent);
        return null;
    }

    /**
     * 把图片名列表追加到消息正文末尾，格式与单词报错保持一致（【报错图片】+ JSON 数组），
     * 这样两端的解析工具只需要认识一种写法。没有图片时正文原样返回。
     */
    private String appendImageFiles(String content, String imageFiles) {
        if (imageFiles == null || imageFiles.trim().isEmpty()) {
            return content;
        }
        return content + "\n" + IMAGE_FILES_MARKER + imageFiles.trim();
    }

    /**
     * 管理员回复某个用户的意见，可随回复附上截图。
     *
     * @param referenceMsgId 被回复的那条消息ID，为空表示不是针对某条消息的回复；
     *                       非空时必须真实存在、且确实是该用户发给客服的消息，否则直接拒绝
     * @param imageFiles 随回复一起发出去的截图名列表（JSON 数组），由本方法统一拼进正文
     */
    public void replyAdvice(String content, User toUser, UserBo userBo, String referenceMsgId, String imageFiles) {
        Msg referenceMsg = null;
        if (StringUtils.hasText(referenceMsgId)) {
            referenceMsg = findById(referenceMsgId);
            if (referenceMsg == null) {
                throw new IllegalArgumentException("被回复的消息不存在，可能已被删除");
            }
            if (referenceMsg.getFromUser() == null || !toUser.getId().equals(referenceMsg.getFromUser().getId())) {
                throw new IllegalArgumentException("被回复的消息不属于该用户，拒绝回复");
            }
        }

        Msg msg = createMsg(appendImageFiles(content, imageFiles), MsgType.AdviceReply,
                userBo.getSysUser_sys(false), toUser);
        if (referenceMsg != null) {
            msg.setReplyToId(referenceMsg.getId());
            try {
                updateEntity(msg);
            } catch (IllegalAccessException e) {
                throw new IllegalStateException("写入被引用消息失败: msgId=" + msg.getId(), e);
            }
        }

        // 向用户推送通知，告知最新的消息数量情况
        SocketService.getInstance().sendPersistentMsgCountToUser(userBo.getUserVoById(toUser.getId()));
    }

    public Msg createMsg(String content, MsgType msgType, String clientType, User fromUser, User toUser) {
        Msg msg = new Msg(msgType);
        msg.setFromUser(fromUser);
        msg.setToUser(toUser);
        msg.setContent(content);
        msg.setViewed(false);
        msg.setCreateTime(new Date());

        if (StringUtils.hasText(clientType)) {
            try {
                msg.setClientType(ClientType.valueOf(clientType));
            } catch (IllegalArgumentException e) {
                // 客户端类型无效时留空，不阻断消息落库
                logger.warn("无效的客户端类型: {}", clientType);
            }
        }

        createEntity(msg);
        return msg;
    }

    public Msg createMsg(String content, MsgType msgType, User fromUser, User toUser) {
        return createMsg(content, msgType, null, fromUser, toUser);
    }

    /**
     * 把某用户的若干指定消息（发往该用户或该用户发起的消息）置为已读
     *
     * @param msgIds
     */
    public void setMsgsAsViewed(List<String> msgIds, String userId, UserBo userBo) {
        // 没有需要置为已读的消息时，视为空操作，避免 `IN ()` 非法 SQL 或空列表被拒
        if (msgIds == null || msgIds.isEmpty()) {
            return;
        }

        String sql = "UPDATE msg SET viewed = true WHERE id IN (:ids) AND (to_user_id = :userId OR from_user_id = :userId)";
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
    /**
     * 清理指定天数以前的意见建议消息
     *
     * @param daysAge 天数
     * @return 删除的记录数
     */
    public int cleanupOldAdvice(int daysAge) {
        Date threshold = new Date(System.currentTimeMillis() - (long) daysAge * 24 * 60 * 60 * 1000);
        // 保护两类消息不被批量清理误删：打了标签（如“需求”）的宝贵反馈，以及已经被回复引用的消息
        String sql = "DELETE FROM msg WHERE msg_type = :msgType AND (tag IS NULL OR tag = '')"
                + " AND reply_to_id IS NULL AND create_time < :threshold";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("msgType", MsgType.Advice.toString());
        params.addValue("threshold", threshold);
        int deletedCount = namedParameterJdbcTemplate.update(sql, params);
        logger.info("清理了 {} 条 {} 天前未打标的意见建议消息", deletedCount, daysAge);
        return deletedCount;
    }

    /**
     * 删除指定消息。已经被回复引用的消息不允许删除——引用块会指向一条不存在的消息，
     * 用户看到的将是“原消息已删除”，等于悄悄丢掉了上下文。要求先删引用它的回复。
     *
     * @param msgId 消息ID
     */
    public void deleteMsg(String msgId) {
        String referenceSql = "SELECT COUNT(*) FROM msg WHERE reply_to_id = :id";
        Long referenceCount = namedParameterJdbcTemplate.queryForObject(referenceSql,
                new MapSqlParameterSource("id", msgId), Long.class);
        if (referenceCount != null && referenceCount > 0) {
            throw new IllegalArgumentException("该消息已被 " + referenceCount + " 条回复引用，请先删除引用它的回复");
        }

        String sql = "DELETE FROM msg WHERE id = :id";
        MapSqlParameterSource params = new MapSqlParameterSource("id", msgId);
        namedParameterJdbcTemplate.update(sql, params);
        logger.info("已删除消息: msgId={}", msgId);
    }

    /**
     * 更新消息的管理员业务标签（如“需求”，传入空或 null 则清空标签）。
     *
     * 打标签就只是给这条消息贴一个标签，不附带任何处理状态或阶段：
     * 消息级需求与需求墙是两套数据，不打标即不是需求，取消标记即清空标签。
     *
     * @param msgId 消息ID
     * @param tag 标签文本
     */
    public void updateMsgTag(String msgId, String tag) {
        String normalizedTag = StringUtils.hasText(tag) ? tag.trim() : null;

        String sql = "UPDATE msg SET tag = :tag WHERE id = :id";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("id", msgId);
        params.addValue("tag", normalizedTag);
        namedParameterJdbcTemplate.update(sql, params);

        logger.info("已更新消息标签: msgId={}, tag={}", msgId, normalizedTag);
    }

    /**
     * 客服会话摘要（管理员功能）：一个用户一行，带未读条数与含需求条数。
     *
     * 一次查询拿到全部统计，避免管理端先拉全量意见建议再在客户端按人平铺。
     *
     * @param limit 最多返回多少个会话（按最后一条消息时间倒序，取最近有互动的）
     */
    public List<AdviceSessionVo> getAdviceSessions(int limit) {
        String sql = "SELECT u.id AS user_id, u.user_name AS user_name, u.nick_name AS nick_name,"
                + " u.wechat_avatar AS wechat_avatar, u.premium_override_enabled AS premium,"
                + " s.unviewed_count, s.total_count, s.requirement_count,"
                + " SUBSTRING(s.last_content FROM 1 FOR 60) AS last_content,"
                + " s.last_msg_type, s.last_create_time"
                + " FROM ("
                + "   SELECT from_user_id,"
                + "     COUNT(*) FILTER (WHERE viewed = false) AS unviewed_count,"
                + "     COUNT(*) AS total_count,"
                + "     COUNT(*) FILTER (WHERE tag = :requirementTag) AS requirement_count,"
                + "     MAX(create_time) AS last_create_time,"
                + "     (ARRAY_AGG(content ORDER BY create_time DESC, id DESC))[1] AS last_content,"
                + "     (ARRAY_AGG(msg_type ORDER BY create_time DESC, id DESC))[1] AS last_msg_type"
                + "   FROM msg WHERE msg_type = :msgType AND to_user_id = :sysUserId"
                + "   GROUP BY from_user_id"
                + " ) s JOIN \"user\" u ON u.id = s.from_user_id"
                + " ORDER BY s.unviewed_count DESC, s.last_create_time DESC"
                + " LIMIT :limit";

        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("msgType", MsgType.Advice.toString());
        params.addValue("sysUserId", Constants.SYS_USER_SYS_ID);
        params.addValue("requirementTag", REQUIREMENT_TAG);
        params.addValue("limit", limit);

        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            AdviceSessionVo vo = new AdviceSessionVo();
            vo.setUserId(rs.getString("user_id"));
            vo.setUserName(rs.getString("user_name"));
            vo.setNickName(rs.getString("nick_name"));
            vo.setWechatAvatar(rs.getString("wechat_avatar"));
            vo.setPremium(rs.getBoolean("premium"));
            vo.setUnviewedCount(rs.getInt("unviewed_count"));
            vo.setTotalCount(rs.getInt("total_count"));
            vo.setRequirementCount(rs.getInt("requirement_count"));
            vo.setLastContent(rs.getString("last_content"));
            vo.setLastMsgType(toMsgType(rs.getString("last_msg_type")));
            vo.setLastCreateTime(rs.getTimestamp("last_create_time"));
            return vo;
        });
    }

    /**
     * 消息级需求列表（管理员功能）：被标记为需求的消息，按时间倒序。
     *
     * 只有「被标过需求」这一个条件，没有状态可分栏——打标签本身就是全部。
     */
    public List<AdviceRequirementVo> getAdviceRequirements() {
        String sql = "SELECT m.id, m.content, m.create_time, m.client_type, m.from_user_id,"
                + " u.user_name, u.nick_name, u.wechat_avatar, u.premium_override_enabled"
                + " FROM msg m JOIN \"user\" u ON u.id = m.from_user_id"
                + " WHERE m.tag = :requirementTag"
                + " ORDER BY m.create_time DESC";

        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("requirementTag", REQUIREMENT_TAG);

        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            AdviceRequirementVo vo = new AdviceRequirementVo();
            vo.setId(rs.getString("id"));
            vo.setContent(rs.getString("content"));
            vo.setCreateTime(rs.getTimestamp("create_time"));
            vo.setClientType(toClientType(rs.getString("client_type")));
            vo.setUserId(rs.getString("from_user_id"));
            vo.setUserName(rs.getString("user_name"));
            vo.setNickName(rs.getString("nick_name"));
            vo.setWechatAvatar(rs.getString("wechat_avatar"));
            vo.setPremium(rs.getBoolean("premium_override_enabled"));
            return vo;
        });
    }

    /**
     * 查出一些消息分别引用了哪条消息，把被引用消息的类型与正文填进 VO，供界面画引用块。
     * 被引用的消息已经不存在时不填（界面会显示“原消息已删除”），不允许静默当成没有引用。
     */
    public void fillQuotedMessages(List<MsgVo> vos) {
        if (vos == null || vos.isEmpty()) {
            return;
        }

        Set<String> quotedIds = new HashSet<>();
        for (MsgVo vo : vos) {
            if (StringUtils.hasText(vo.getReplyToId())) {
                quotedIds.add(vo.getReplyToId());
            }
        }
        if (quotedIds.isEmpty()) {
            return;
        }

        String sql = "SELECT * FROM msg WHERE id IN (:ids)";
        List<Msg> quotedMsgs = namedParameterJdbcTemplate.query(sql,
                new MapSqlParameterSource("ids", quotedIds), new EntityRowMapper<>(Msg.class));

        Map<String, Msg> quotedMap = new HashMap<>();
        for (Msg quoted : quotedMsgs) {
            quotedMap.put(quoted.getId(), quoted);
        }

        for (MsgVo vo : vos) {
            if (!StringUtils.hasText(vo.getReplyToId())) {
                continue;
            }
            Msg quoted = quotedMap.get(vo.getReplyToId());
            if (quoted == null) {
                continue;
            }
            vo.setQuotedMsgId(quoted.getId());
            vo.setQuotedMsgType(quoted.getMsgType());
            vo.setQuotedContent(quoted.getContent());
        }
    }

    private MsgType toMsgType(String value) {
        if (!StringUtils.hasText(value)) {
            return null;
        }
        try {
            return MsgType.valueOf(value);
        } catch (IllegalArgumentException e) {
            logger.warn("无法识别的消息类型: {}", value);
            return null;
        }
    }

    private ClientType toClientType(String value) {
        if (!StringUtils.hasText(value)) {
            return null;
        }
        try {
            return ClientType.valueOf(value);
        } catch (IllegalArgumentException e) {
            logger.warn("无法识别的客户端类型: {}", value);
            return null;
        }
    }

}
