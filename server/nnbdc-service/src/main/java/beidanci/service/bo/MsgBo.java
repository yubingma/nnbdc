package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.Date;
import java.util.List;

import org.hibernate.Session;
import org.hibernate.query.Query;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.MsgType;
import beidanci.api.model.PagedResults;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.Msg;
import beidanci.service.po.User;
import beidanci.service.socket.SocketService;
import beidanci.service.util.Util;
import beidanci.util.Constants;

@Service
@Transactional(rollbackFor = Throwable.class)
public class MsgBo extends BaseBo<Msg> {
    @Autowired
    UserBo userBo;

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
        // 查询一页数据
        Session session = getSession();
        String baseHql = "from Msg m where m.id=(select max(mm.id) from Msg mm where mm.fromUser = m.fromUser" +
                (toUserId == null ? "" : " and mm.toUser=:toUser") +
                (msgType == null ? "" : " and mm.msgType=:msgType") +
                ") order by m.updateTime desc";
        String hql = "select m " + baseHql;
        Query<Msg> query = session.createQuery(hql, Msg.class);
        if (toUserId != null) {
            query.setParameter("toUser", userBo.findById(toUserId));
        }
        if (msgType != null) {
            query.setParameter("msgType", msgType);
        }
        query.setFirstResult((page - 1) * rows);
        query.setMaxResults(rows);
        List<Msg> msgs = query.list();

        // 查询数据总条数
        hql = "select count(*) " + baseHql;
        Query<Long> query2 = session.createQuery(hql, Long.class);
        if (toUserId != null) {
            query2.setParameter("toUser", userBo.findById(toUserId));
        }
        if (msgType != null) {
            query2.setParameter("msgType", msgType);
        }
        long total = query2.uniqueResult();

        PagedResults<Msg> pagedResults = new PagedResults<>();
        pagedResults.setTotal((int) total);
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
        User user1_ = userBo.findById(user1);
        User user2_ = userBo.findById(user2);

        Session session = getSession();
        String baseHql = "from Msg m where (fromUser = :user1 and toUser = :user2) or (fromUser = :user2 and toUser = :user1) order by createTime asc";

        // 查询数据总条数
        Query<Long> query2 = session.createQuery("select count(*) " + baseHql, Long.class);
        query2.setParameter("user1", user1_);
        query2.setParameter("user2", user2_);
        int total = query2.uniqueResult().intValue();

        // 查询数据
        Query<Msg> query = session.createQuery(baseHql, Msg.class);
        query.setParameter("user1", user1_);
        query.setParameter("user2", user2_);
        query.setFirstResult(total >= msgCount ? total - msgCount : 0);
        query.setMaxResults(msgCount);

        return query.list();
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
        User toUser = userBo.findById(toUserId);

        Session session = getSession();
        String hql = "select count(*) from Msg m where toUser = :toUser and viewed = false";

        // 查询数据总条数
        Query<Long> query2 = session.createQuery(hql, Long.class);
        query2.setParameter("toUser", toUser);
        int count = query2.uniqueResult().intValue();

        return count;
    }

    /**
     * 获取发往指定用户的所有持久消息数量
     *
     * @return
     */
    public int getAllPersistentMsgCountToUser(String toUserId) {
        User toUser = userBo.findById(toUserId);

        Session session = getSession();
        String hql = "select count(*) from Msg m where toUser = :toUser";

        // 查询数据总条数
        Query<Long> query2 = session.createQuery(hql, Long.class);
        query2.setParameter("toUser", toUser);
        int count = query2.uniqueResult().intValue();

        return count;
    }

    public void sendAdvice(String content, User fromUser) {
        createMsg(content, MsgType.Advice, fromUser, userBo.getSysUser_sys(false));
        Util.sendEmailToNnbdcCustomerSerivce(String.format("来自[%s]的意见", fromUser.getNickName()), content);
    }

    public void replyAdvice(String content, User toUser, UserBo userBo) {
        createMsg(content, MsgType.AdviceReply, userBo.getSysUser_sys(false), toUser);

        // 向用户推送通知，告知最新的消息数量情况
        SocketService.getInstance().sendPersistentMsgCountToUser(userBo.getUserVoById(toUser.getId()));
    }

    public void createMsg(String content, MsgType msgType, User fromUser, User toUser) {
        Msg msg = new Msg(msgType);
        msg.setFromUser(fromUser);
        msg.setToUser(toUser);
        msg.setContent(content);
        msg.setViewed(false);
        msg.setCreateTime(new Date());
        createEntity(msg);
    }

    /**
     * 把某用户的若干指定消息（发往该用户或该用户发起的消息）置为已读
     *
     * @param msgIds
     */
    public void setMsgsAsViewed(List<String> msgIds, String userId, UserBo userBo) {
        User user = userBo.findById(userId);

        Session session = getSession();
        String hql = "update Msg set viewed = 1 where id IN :ids and (toUser=:user or fromUser=:user)";
        Query<?> query2 = session.createQuery(hql);
        query2.setParameter("ids", msgIds);
        query2.setParameter("user", user);
        query2.executeUpdate();

        // 向用户推送通知，告知最新的消息数量情况
        SocketService.getInstance().sendPersistentMsgCountToUser(userBo.getUserVoById(userId));
    }
}
