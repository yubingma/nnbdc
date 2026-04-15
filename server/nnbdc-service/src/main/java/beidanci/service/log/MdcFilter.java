package beidanci.service.log;

import beidanci.service.bo.UserBo;
import beidanci.service.po.User;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.core.annotation.Order;

/**
 * 将用户信息和客户端平台信息注入日志上下文 (MDC)
 */
@Component
@Order(-110)
public class MdcFilter extends OncePerRequestFilter {

    @Autowired
    private UserBo userBo;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        
        String userId = request.getParameter("userId");
        String userContext = "";
        if (userId != null && !userId.isEmpty()) {
            try {
                User user = userBo.findById(userId);
                if (user != null) {
                    userContext = user.getDisplayNickName() + "(" + userId + ")";
                } else {
                    userContext = userId;
                }
            } catch (Exception ignore) {}
        }
        MDC.put("userContext", userContext);

        String userAgent = request.getHeader("User-Agent");
        String platform = "Unknown";
        if (userAgent != null) {
            String ua = userAgent.toLowerCase();
            if (ua.contains("iphone") || ua.contains("ipad")) platform = "iOS";
            else if (ua.contains("android")) platform = "Android";
            else if (ua.contains("windows")) platform = "Windows";
            else if (ua.contains("macintosh")) platform = "macOS";
            else if (ua.contains("mozilla")) platform = "Web";
        }
        MDC.put("platform", platform);

        try {
            filterChain.doFilter(request, response);
        } finally {
            MDC.remove("userContext");
            MDC.remove("platform");
        }
    }
}
