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
        if (e instanceof IOException && e.getMessage() != null) {
            String msg = e.getMessage().toLowerCase();
            if (msg.contains("connection reset")
                    || msg.contains("broken pipe")
                    || msg.contains("connection timed out")
                    || msg.contains("eofexception")
                    || msg.contains("连接被对方重设")) {
                return true;
            }
        }
        log.warn("", e);
        ctx.close();
        return true;
    }
}
