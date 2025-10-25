package beidanci.service.socket;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.util.Assert;

import com.corundumstudio.socketio.AckRequest;
import com.corundumstudio.socketio.BroadcastOperations;
import com.corundumstudio.socketio.SocketIOClient;
import com.corundumstudio.socketio.SocketIONamespace;

import beidanci.api.ChatObject;
import beidanci.api.model.MsgVo;
import beidanci.api.model.UserVo;
import beidanci.service.bo.MsgBo;
import beidanci.service.bo.UserBo;
import beidanci.service.socket.system.MySystem;
import beidanci.service.util.Util;

public class SocketService {
    private static final Logger log = LoggerFactory.getLogger(SocketService.class);
    private static SocketService instance;

    private final Map<String, MySystem> systems;

    MsgBo msgBo;

    UserBo userBo;


    public static SocketService getInstance() {
        return instance;
    }

    @SuppressWarnings("this-escape")
    public SocketService(SocketIONamespace namespace, SocketServer socketServer, Map<String, MySystem> systems, MsgBo msgBo,
                         UserBo userBo) {
        if (instance != null) {
            throw new RuntimeException("SocketService has been created more than once.");
        }
        
        this.namespace = namespace;
        this.socketServer = socketServer;
        this.systems = systems;
        this.msgBo = msgBo;
        this.userBo = userBo;

        initListeners();

        // 将instance赋值移到构造函数最后，避免this逃逸
        instance = this;

    }

    protected void onUserLogout(UserVo user) throws IllegalAccessException {
        for (MySystem sys : systems.values()) {
            sys.onUserLogout(user);
        }

        broadcastOnelineUserCount();
    }

    protected List<UserVo> getIdleUsers(UserVo except, int count) {
        List<UserVo> idleUsers = new ArrayList<>();
        for (MySystem sys : systems.values()) {
            List<UserVo> users = sys.getIdleUsers(except, count);
            for (UserVo user : users) {
                idleUsers.add(user);
                if (idleUsers.size() >= count) {
                    return idleUsers;
                }
            }
        }
        return idleUsers;
    }

    protected void onUserLogin(UserVo user) {

    }

    protected SocketIONamespace namespace;

    /**
     * 本服务的所有在线用户Session，key为user name
     */
    protected Map<String, UUID> sessionsByUser = new ConcurrentHashMap<>();

    /**
     * 本服务的所有在线用户，key为Session ID
     */
    protected Map<UUID, UserVo> usersBySession = new ConcurrentHashMap<>();

    /**
     * 本服务的所有用户socket clients, key为session ID
     */
    private final Map<UUID, SocketIOClient> clientsBySession = new ConcurrentHashMap<>();

    private final SocketServer socketServer;

    /**
     * 广播有用户上线了
     *
     * @param user
     */
    public void broadcastUserOnline(UserVo user) {
        namespace.getBroadcastOperations().sendEvent("userOnline", Util.getNickNameOfUser(user));
        broadcastOnelineUserCount();
    }

    /**
     * 广播有用户下线了
     *
     * @param user
     */
    public void broadcastUserOffline(UserVo user) {
        namespace.getBroadcastOperations().sendEvent("userOffline", Util.getNickNameOfUser(user));
        broadcastOnelineUserCount();
    }

    /**
     * 广播在线用户数量
     */
    public void broadcastOnelineUserCount() {
        namespace.getBroadcastOperations().sendEvent("onlineCount", String.valueOf(sessionsByUser.size()));
    }

    /**
     * 关闭用户的现有连接
     *
     * @param user
     * @return true 表示真正删除发现用户存在现有连接并已将之关闭，false表示用户并没有现有连接
     */
    public boolean disconnectExistingConnectionOfUser(UserVo user, SocketIOClient newClient, String reason) {
        UUID sessionId = sessionsByUser.get(user.getId());
        if (sessionId != null) {
            SocketIOClient existingClient = clientsBySession.get(sessionId);
            Assert.notNull(existingClient, "existingClient is null");
            if (existingClient != newClient) {
                log.debug(String.format("关闭了用户[%s]的现有连接（%s|%s）, 原因: %s", user.getDisplayNickName(),
                        existingClient.getRemoteAddress(), existingClient.getSessionId(), reason));
                existingClient.sendEvent("forceClose", reason);
                existingClient.sendEvent("msg", new ChatObject(userBo.getSysUser_sys(true).getId(), "系统",
                        String.format("连接被关闭, 原因: %s", reason)));
                existingClient.disconnect();
                clearUserCache(user.getId(), sessionId);
                return true;
            }
        }
        return false;
    }

    public void addUserCache(UserVo user, SocketIOClient client) {
        UUID sessionId = client.getSessionId();
        sessionsByUser.put(user.getId(), sessionId);
        usersBySession.put(sessionId, user);
        clientsBySession.put(sessionId, client);
        checkCache();
    }

    private void clearUserCache(String userId, UUID sessionId) {
        UUID session = (sessionsByUser.remove(userId));
        Assert.isTrue(sessionId.equals(session),
                String.format("sessionId:%s, session:%s", sessionId, session));

        UserVo user = usersBySession.remove(sessionId);
        Assert.isTrue(userId.equals(user.getId()), String.format("userId:%s, user.getId():%s", userId, user.getId()));

        SocketIOClient client = clientsBySession.remove(sessionId);
        Assert.isTrue(sessionId.equals(client.getSessionId()), String.format("sessionId:%s, client.getSessionId():%s", sessionId, client.getSessionId()));
        checkCache();
    }

    private void checkCache() {
        boolean ok = usersBySession.size() == sessionsByUser.size() && usersBySession.size() == clientsBySession.size();
        if (!ok) {
            log.warn(String.format(
                    "Cache is not in good staus. usersBySession[%d] sessionsByUser[%d] clientsBySession[%d]",
                    usersBySession.size(), sessionsByUser.size(), clientsBySession.size()));
        }
    }

    private void initListeners() {

        namespace.addConnectListener((SocketIOClient client) -> log.info(String.format("Accepted a new connection: %s", client.getRemoteAddress())));

        namespace.addDisconnectListener((SocketIOClient client) -> {
            try {
                UUID sessionId = client.getSessionId();
                UserVo userVo = usersBySession.get(sessionId);
                if (userVo != null) {
                    log.info(String.format("与用户[%s]的连接中断！", userVo.getDisplayNickName()));
                    clearUserCache(userVo.getId(), sessionId);

                    broadcastUserOffline(userVo);
                    onUserLogout(userVo);
                }else{
                    log.info(String.format("与%s的连接中断！", client.getRemoteAddress()));
                }
            } catch (IllegalAccessException e) {
                log.error("", e);

            }
        });

        namespace.addEventListener("heartBeat", String.class, (SocketIOClient client, String data, AckRequest ackSender) -> {
            try {
                socketServer.onHeartBeatReceived(client);
            } catch (Exception e) {
                log.error("", e);
            }
        });

        namespace.addEventListener("reportUser", String.class, (SocketIOClient client, String theUserId, AckRequest ackSender) -> {
            try {
                final String userId = theUserId;

                // 根据ID查找相应用户
                UserVo user = null;
                try {
                    user = userBo.getUserVoById(userId);

                    if (user == null) {
                        log.error(String.format("在数据库中找不到用户【%s】", theUserId));
                        return;
                    }

                } catch (Exception e) {
                    log.error("", e);
                }

                // 关闭用户其他的连接，因为只允许一个用户有一个连接
                if (disconnectExistingConnectionOfUser(user, client, "一个用户不允许多个连接")) {
                    broadcastUserOffline(user);
                    onUserLogout(user);
                }

                // 保存用户相关信息到缓存
                final UUID sessionId = client.getSessionId();
                if (usersBySession.containsKey(sessionId)) {// 客户端到socket
                    // server的连接是长连接，即使客户端切换了登录用户，连接也是一直存在的，所以存在多个用户通过同一个连接上报的情况，此时应将之前登录用户的信息清除
                    UserVo oldUser = usersBySession.get(sessionId);
                    clearUserCache(oldUser.getId(), sessionId);
                }
                addUserCache(user, client);

                // 向所有玩家广播新用户上线信息
                broadcastUserOnline(user);
                log.info(String.format("用户[%s]上线，在线用户数[%d]", Util.getNickNameOfUser(user), sessionsByUser.size()));
                onUserLogin(user);

                // 向该用户发送 未读/所有 持久消息数量
                sendPersistentMsgCountToUser(user);
            } catch (IllegalAccessException e) {
                log.error("", e);
            }
        });

        namespace.addEventListener("getIdleUsers", Integer.class, (SocketIOClient client, Integer count, AckRequest ackSender) -> {
            try {
                UserVo user = usersBySession.get(client.getSessionId());
                sendEventToUser(user, "idleUsers", getIdleUsers(user, count));
            } catch (Exception e) {
                log.error("", e);
            }
        });

        namespace.addEventListener("userCmd", UserCmd.class, (SocketIOClient client, UserCmd userCmd, AckRequest ackSender) -> {
            try {
                final UserVo user = usersBySession.get(client.getSessionId());
                if (user == null) {// 找不到与session ID对应的用户，说明用户尚未上报，这种情况可能出现在服务端重启后
                    return;
                }
                assert (userCmd.getUserId().equals(user.getId()));

                userCmd.setUserBo(userBo);
                MySystem mySystem = systems.get(userCmd.getSystem());
                mySystem.processUserCmd(user, userCmd);
            } catch (Exception e) {
                log.error("", e);
            }
        });
    }

    /**
     * 向指定用户发送该用户的 未读/所有 持久消息数量
     *
     * @param user
     */
    public void sendPersistentMsgCountToUser(UserVo user) {
        int unreadPersistentMsgCount = msgBo.getUnViewedPersistentMsgCountToUser(user.getId());
        int allPersistentMsgCount = msgBo.getAllPersistentMsgCountToUser(user.getId());
        sendEventToUser(user, "persistentMsgCount", new Integer[]{unreadPersistentMsgCount, allPersistentMsgCount});
    }

    public void sendEventToUser(UserVo user, String event, Object data) {
        final UUID sessionId = sessionsByUser.get(user.getId());
        if (sessionId != null) {
            SocketIOClient client = clientsBySession.get(sessionId);
            client.sendEvent(event, data);
        }
    }

    public void sendEventToUser(String targetUserId, String event, Object data) {
        UserVo targetUser = getUserById(targetUserId);
        if (targetUser != null) {
            sendEventToUser(targetUser, event,
                    data);
        }
    }

    public void sendMsgToUser(String targetUserId, MsgVo msg) {
        UserVo targetUser = getUserById(targetUserId);
        if (targetUser != null) {
            sendEventToUser(targetUser, "msg",
                    msg);
        }
    }


    /**
     * Socket Server 通过本函数通知本服务某个session对应的连接被关闭了
     */
    public void onConnnectionBroken(UUID sessionId, String reason) throws IllegalAccessException {
        UserVo user = usersBySession.get(sessionId);
        if (user != null) {
            disconnectExistingConnectionOfUser(user, null, reason);

            for (MySystem sys : systems.values()) {
                sys.onConnectionBroken(user, reason);
            }
        }

        broadcastOnelineUserCount();
    }

    public UserVo getUserById(String userId) {
        for (UserVo user : usersBySession.values()) {
            if (user.getId().equals(userId)) {
                return user;
            }
        }
        return null;
    }

    public List<UserVo> getUsers() {
        return new ArrayList<>(usersBySession.values());
    }

    public BroadcastOperations getBroadcastOperations() {
        return namespace.getBroadcastOperations();
    }
}
