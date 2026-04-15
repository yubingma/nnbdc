package beidanci.service.log;

import java.io.IOException;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;

import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.slf4j.MDC;
import org.springframework.core.annotation.Order;
import org.springframework.lang.NonNull;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Mapped Diagnostic Context (MDC) 过滤器。
 * <p>
 * MDC 是日志框架（SLF4J/Logback）提供的一种机制，用于在多线程环境下管理诊断上下文信息。
 * 本过滤器在请求进入后端时，从 HTTP 头部提取用户信息（ID、昵称）和客户端平台信息，并将其存入 MDC。
 * </p>
 * <p>
 * 核心作用：
 * 1. 自动增强日志：使所有业务日志（Service/DAO层）都能自动包含用户信息，无需手动传递参数。
 * 2. 跨线程传播：配合 {@code MDC.getCopyOfContextMap()} 可将环境信息传递给异步子线程（如 AI 聊天执行器）。
 * 3. 性能优化：直接从 Headers 读取，避免了每条请求都去数据库查询用户信息。
 * </p>
 */
@Component
@Order(-110)
public class MdcFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(@NonNull HttpServletRequest request, @NonNull HttpServletResponse response, @NonNull FilterChain filterChain)
            throws ServletException, IOException {
        
        String userId = request.getHeader("X-User-Id");
        if (userId == null || userId.isEmpty()) {
            userId = request.getParameter("userId");
        }

        String nickname = request.getHeader("X-User-Nickname");
        if (nickname != null && !nickname.isEmpty()) {
            try {
                nickname = URLDecoder.decode(nickname, StandardCharsets.UTF_8.name());
            } catch (Exception ignore) {}
        }

        String userContext = "";
        if (userId != null && !userId.isEmpty()) {
            String shortId = userId.substring(0, Math.min(6, userId.length()));
            if (nickname != null && !nickname.isEmpty()) {
                userContext = nickname + "(" + shortId + ")";
            } else {
                userContext = shortId;
            }
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
