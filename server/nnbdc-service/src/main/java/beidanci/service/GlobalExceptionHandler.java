package beidanci.service;

import java.io.IOException;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.apache.catalina.connector.ClientAbortException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.lang.NonNull;
import org.springframework.lang.Nullable;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerExceptionResolver;
import org.springframework.web.servlet.ModelAndView;

import beidanci.service.util.Util;

@Component
public class GlobalExceptionHandler implements HandlerExceptionResolver {
    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @Override
    public ModelAndView resolveException(@NonNull HttpServletRequest request, @NonNull HttpServletResponse response, @Nullable Object handler,
                                         @NonNull Exception e) {


        // 客户端在接收完应答前终止了，这种异常不需要处理，由框架层自行处理
        if (e instanceof ClientAbortException) {
            log.info("客户端在访问[{}]时终止", request.getRequestURI());
            return null;
        }

        log.error(String.format("访问[%s]时出现异常", request.getRequestURI()), e);

        try {
            response.setStatus(500);
            Util.sendBooleanResponse(false, "系统异常:" + e.getMessage(), null, response);
        } catch (IOException e1) {
            log.error("", e1);
        }
        return new ModelAndView(); // 这里new一个空的ModelAndView而不是返回null，是为了告诉底层异常已被处理了。

    }

}
