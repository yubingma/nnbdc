package beidanci.service.socket;

import java.util.Date;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.corundumstudio.socketio.Configuration;
import com.corundumstudio.socketio.SocketIOClient;
import com.corundumstudio.socketio.SocketIONamespace;
import com.corundumstudio.socketio.SocketIOServer;

import beidanci.service.MyExceptionListener;
import beidanci.service.bo.MsgBo;
import beidanci.service.bo.UserBo;
import beidanci.service.socket.system.MySystem;
import beidanci.service.socket.system.chat.Chat;
import beidanci.service.socket.system.game.russia.Russia;
import beidanci.service.util.SysParamUtil;

@Component
public class SocketServer {
    private static final Logger log = LoggerFactory.getLogger(SocketServer.class);

    private boolean isStarted = false;
    private SocketIOServer server;
    private SocketService socketService;
    private final Map<UUID, SocketClientData> socketIOClients = new ConcurrentHashMap<>();
    private final Timer timer;

    @Autowired
    Russia russia;

    @Autowired
    Chat chat;

    @Autowired
    MsgBo msgBo;

    @Autowired
    SysParamUtil sysParamUtil;

    @Autowired
    UserBo userBo;

    public SocketServer() {
        timer = new Timer();
        timer.scheduleAtFixedRate(new CheckHeartBeatTask(), 0, 5 * 1000);
    }

    private class CheckHeartBeatTask extends TimerTask {

        @Override
        public void run() {

            try {
                for (Iterator<SocketClientData> i = socketIOClients.values().iterator(); i.hasNext(); ) {
                    SocketClientData socketClientData = i.next();
                    SocketIOClient socketClient = socketClientData.getSocketIOClient();
                    Date lastHeartBeatTime = socketClientData.getLastHeartBeatTime();

                    // 15秒没有听到客户端心跳，即杀掉连接
                    if (new Date().getTime() - lastHeartBeatTime.getTime() > 15 * 1000) {
                        log.debug(String.format("心跳超时，关闭连接: %s|%s", socketClient.getRemoteAddress(),
                                socketClient.getSessionId()));
                        socketClient.disconnect();
                        i.remove();

                        // 通知上层服务连接已经关闭了
                        socketService.onConnnectionBroken(socketClient.getSessionId(), "心跳超时");
                    }
                }
            } catch (IllegalAccessException e) {
                log.error("", e);
            }
        }

    }

    public void onHeartBeatReceived(SocketIOClient client) {
        SocketClientData socketClientData = socketIOClients.get(client.getSessionId());
        if (socketClientData != null) {
            socketClientData.setLastHeartBeatTime(new Date());
            socketIOClients.put(client.getSessionId(), socketClientData);
        } else {
            // 当服务端发现客户端心跳超时后，会调用SocketIOClient.disconnect()关闭连接，但是该方法的并不会强行关闭
            // Socket连接，而是通过向客户端发送通知消息，希望双方能够优雅的关闭连接，但如果此时网络不畅，客户端收不到
            // 通知，就会导致连接长时间得不到释放。
            // 如果服务端认为一个连接已经被disconnect了，但又收到了该连接的心跳，那么就应该再次尝试进行SocketIOClient.disconnect()
            log.warn(String.format("收到来自 %s 的心跳连接，但是SocketServer没有该连接的信息，再次尝试disconnect该连接", client.getRemoteAddress()));
            client.disconnect();
        }
    }

    public void start() {
        if (!sysParamUtil.isGameEnabled()) {
            log.info("系统参数[gameEnabled]值为false，不启动socket server");
            return;
        }


        if (isStarted) {
            throw new RuntimeException(this.getClass().getSimpleName() + " already started.");
        }

        Configuration config = new Configuration();
        config.setHostname(sysParamUtil.getSocketServerAddr());
        config.setPort(sysParamUtil.getSocketServerPort());
        config.setExceptionListener(new MyExceptionListener());

        server = new SocketIOServer(config);

        server.addConnectListener((SocketIOClient client) -> {
            try {
                socketIOClients.put(client.getSessionId(), new SocketClientData(client, new Date()));
                log.debug(String.format("新建连接:%s|%s", client.getRemoteAddress(), client.getSessionId()));
            } catch (Exception e) {
                log.error("", e);
            }
        });

        server.addDisconnectListener((SocketIOClient client) -> {
            try {
                log.debug(String.format("连接关闭:%s|%s", client.getRemoteAddress(), client.getSessionId()));
                socketIOClients.remove(client.getSessionId());
            } catch (Exception e) {
                log.error("", e);
            }
        });

        Map<String, MySystem> systems = new HashMap<>();
        systems.put(russia.getName(), russia);
        systems.put(chat.getName(), chat);
        final SocketIONamespace socketIONamespace = server.addNamespace("/all");
        socketService = new SocketService(socketIONamespace, this, systems, msgBo, userBo);

        server.start();
        isStarted = true;
    }

    public void stop() {
        if (isStarted) {
            server.stop();
        }
    }

}
