package beidanci.service.security;

import java.util.Arrays;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;

import beidanci.service.error.ExceptionHandlerFilter;

@Configuration
public class WebSecurityConfig {

    @Value("${spring.application.name}")
    private String applicationName;

    @Bean
    public ExceptionHandlerFilter exceptionHandlerFilterBean() {
        return new ExceptionHandlerFilter(applicationName);
    }

    /**
     * 允许浏览器跨域访问后端服务
     */
    @Bean
    public FilterRegistrationBean<CorsFilter> filterRegistrationBean() {
        CorsConfiguration corsConfiguration = new CorsConfiguration();
        // 主流做法：允许携带 Cookie/凭证时，不能使用 "*"，必须指定允许的 Origin 白名单/模式
        // 覆盖生产域名 + 本地开发（Flutter Web/调试页面）
        corsConfiguration.setAllowedOriginPatterns(Arrays.asList(
                "http://localhost:*",
                "http://127.0.0.1:*",
                "http://nnbdc.com",
                "http://www.nnbdc.com",
                "https://nnbdc.com",
                "https://www.nnbdc.com"
        ));
        //2.允许任何请求头
        corsConfiguration.addAllowedHeader(CorsConfiguration.ALL);
        //3.允许任何方法
        corsConfiguration.addAllowedMethod(CorsConfiguration.ALL);
        //4.允许凭证
        corsConfiguration.setAllowCredentials(true);
        // 预检请求缓存（浏览器）
        corsConfiguration.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", corsConfiguration);
        CorsFilter corsFilter = new CorsFilter(source);

        FilterRegistrationBean<CorsFilter> filterRegistrationBean = new FilterRegistrationBean<>(corsFilter);
        filterRegistrationBean.setOrder(-101);  // 小于 SpringSecurity Filter的 Order(-100) 即可

        return filterRegistrationBean;
    }
}
