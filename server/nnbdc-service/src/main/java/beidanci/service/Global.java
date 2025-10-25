package beidanci.service;

import org.hibernate.SessionFactory;
import org.springframework.beans.BeansException;
import org.springframework.context.ApplicationContext;
import org.springframework.context.ApplicationContextAware;
import org.springframework.lang.NonNull;
import org.springframework.security.core.session.SessionRegistry;
import org.springframework.stereotype.Component;
import org.springframework.web.context.WebApplicationContext;

import beidanci.service.bo.UserBo;
import beidanci.service.bo.UserGameBo;
import beidanci.service.bo.WordBo;
import beidanci.service.socket.SocketServer;

@Component
public class Global implements ApplicationContextAware {
    private static ApplicationContext webAppCtx;

    @Override
    public void setApplicationContext(@NonNull ApplicationContext applicationContext) throws BeansException {
        Global.webAppCtx = applicationContext;
    }

    private static void ensureInitialized() {
        if (webAppCtx == null) {
            throw new IllegalStateException("Spring WebApplicationContext not initialized; Global.webAppCtx is null");
        }
    }

    public static SessionFactory getSessionFactory() {
        ensureInitialized();
        return (SessionFactory) webAppCtx.getBean("sessionFactory");
    }

    public static SessionRegistry getSessionRegistry() {
        ensureInitialized();
        return (SessionRegistry) webAppCtx.getBean("sessionRegistry");
    }

    public static WordBo getWordBo() {
        ensureInitialized();
        return (WordBo) webAppCtx.getBean("wordBo");
    }

    public static UserBo getUserBo() {
        ensureInitialized();
        return (UserBo) webAppCtx.getBean("userBo");
    }

    public static UserGameBo getUserGameBo() {
        ensureInitialized();
        return (UserGameBo) webAppCtx.getBean("userGameBo");
    }

    public static SocketServer getSocketServer() {
        ensureInitialized();
        return (SocketServer) webAppCtx.getBean("socketServer");
    }

    public static void setWebAppCtx(WebApplicationContext webAppCtx) {
        Global.webAppCtx = webAppCtx;
    }
}
