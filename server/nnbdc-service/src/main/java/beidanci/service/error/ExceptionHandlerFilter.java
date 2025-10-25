package beidanci.service.error;

import java.io.IOException;

import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.lang.NonNull;
import org.springframework.web.filter.OncePerRequestFilter;

import beidanci.api.Result;
import beidanci.service.util.JsonUtils;

/**
 * 全局处理Filter链产生的异常<br>
 * 说明：另外一个全局处理异常的类GlobalExceptionHandler只能处理Controller产生的异常，所以Filter产生的异常需要另行处理
 */
public class ExceptionHandlerFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(ExceptionHandlerFilter.class);
    private final String applicationName;

    public ExceptionHandlerFilter(String applicationName) {
        this.applicationName = applicationName;
    }

    @Override
    public void doFilterInternal(@NonNull HttpServletRequest request, @NonNull HttpServletResponse response, @NonNull FilterChain filterChain) throws ServletException, IOException {
        try {
            log.info("Request URL: {} {}", request.getMethod(), request.getRequestURI());
            long startTime = System.currentTimeMillis();
            filterChain.doFilter(request, response);
            log.info("Request URL: {} {}, 耗时: {}ms", request.getMethod(), request.getRequestURI(), System.currentTimeMillis() - startTime);
        } catch (IOException | ServletException e) {
            log.error("", e);
            String errCode = applicationName + "-EXCEPTION";
            JsonUtils.sendJson(new Result<Void>(errCode, e.getMessage(), null), response);
        }
    }
}
