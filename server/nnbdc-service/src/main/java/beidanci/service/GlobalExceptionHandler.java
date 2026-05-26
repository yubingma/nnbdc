package beidanci.service;

import java.io.IOException;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.lang.NonNull;
import org.springframework.lang.Nullable;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerExceptionResolver;
import org.springframework.web.servlet.ModelAndView;

import beidanci.service.exception.DbVersionNotMatchException;
import beidanci.service.util.Util;

@Component
public class GlobalExceptionHandler implements HandlerExceptionResolver {
    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @Override
    public ModelAndView resolveException(@NonNull HttpServletRequest request, @NonNull HttpServletResponse response, @Nullable Object handler,
                                         @NonNull Exception e) {


        // 客户端在接收完应答前终止了，这种异常不需要处理，由框架层自行处理
        if (Util.isNetworkException(e)) {
            log.info("客户端在访问[{}]时终止: {}", request.getRequestURI(), e.getMessage());
            return new ModelAndView();
        }

        if (e instanceof DbVersionNotMatchException) {
            log.warn("访问[{}]时发生数据库版本不匹配（属于良性并发哨兵拦截，客户端会自动重试自愈）: {}", request.getRequestURI(), e.getMessage());
        } else {
            log.error(String.format("访问[%s]时出现异常", request.getRequestURI()), e);
        }

        try {
            if (!response.isCommitted()) {
                response.setStatus(500);
                Util.sendBooleanResponse(false, e.getMessage(), null, response);
            } else {
                log.warn("无法通过 GlobalExceptionHandler 发送错误响应，响应已提交: {}", request.getRequestURI());
            }
        } catch (IOException e1) {
            log.error("发送异常响应时发生 I/O 错误", e1);
        }
        return new ModelAndView(); // 这里new一个空的ModelAndView而不是返回null，是为了告诉底层异常已被处理了。

    }

}
