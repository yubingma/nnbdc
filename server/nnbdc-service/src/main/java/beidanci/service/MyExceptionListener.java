package beidanci.service;

import com.corundumstudio.socketio.listener.ExceptionListenerAdapter;
import io.netty.channel.ChannelHandlerContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;

public class MyExceptionListener extends ExceptionListenerAdapter {
    private static final Logger log = LoggerFactory.getLogger(MyExceptionListener.class);

    @Override
    public boolean exceptionCaught(ChannelHandlerContext ctx, Throwable e) throws Exception {
        if (e instanceof IOException && e.getMessage() != null
                && (e.getMessage().contains("Connection reset by peer") || e.getMessage().contains("连接被对方重设"))) {
            return true;
        }
        log.warn("", e);
        ctx.close();
        return true;
    }
}
