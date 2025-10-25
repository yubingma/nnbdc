package beidanci.service.socket;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.ContextClosedEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * 在应用启动完成后启动游戏服务器，并在应用关闭时停止
 */
@Component
public class GameServerStarter {
    private static final Logger log = LoggerFactory.getLogger(GameServerStarter.class);

    private final SocketServer socketServer;

    public GameServerStarter(final SocketServer socketServer) {
        this.socketServer = socketServer;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onApplicationReady() {
        try {
            socketServer.start();
            log.info("Socket game server started on application ready.");
        } catch (Exception e) {
            log.error("Failed to start socket game server.", e);
        }
    }

    @EventListener(ContextClosedEvent.class)
    public void onContextClosed() {
        try {
            socketServer.stop();
            log.info("Socket game server stopped on context closed.");
        } catch (Exception e) {
            log.error("Failed to stop socket game server.", e);
        }
    }
}


