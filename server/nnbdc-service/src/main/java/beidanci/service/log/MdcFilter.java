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
            String shortId = userId.substring(0, Math.min(6, userId.length()));
            try {
                User user = userBo.findById(userId);
                if (user != null) {
                    userContext = user.getDisplayNickName() + "(" + shortId + ")";
                } else {
                    userContext = shortId;
                }
            } catch (Exception ignore) {}
        }
        MDC.put("userContext", userContext);

        String platform = request.getHeader("X-Client-Platform");
        if (platform == null || platform.isEmpty() || platform.equalsIgnoreCase("Unknown")) {
            String userAgent = request.getHeader("User-Agent");
            if (userAgent != null) {
                String ua = userAgent.toLowerCase();
                if (ua.contains("iphone") || ua.contains("ipad")) platform = "iOS";
                else if (ua.contains("android")) platform = "Android";
                else if (ua.contains("windows")) platform = "Windows";
                else if (ua.contains("macintosh") || ua.contains("mac os x")) platform = "macOS";
                else if (ua.contains("dart")) platform = "MobileApp";
                else if (ua.contains("mozilla")) platform = "Web";
                else if (ua.contains("postman") || ua.contains("insomnia")) platform = "DevTool";
                else platform = "Unknown";
            } else {
                platform = "Unknown";
            }
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
