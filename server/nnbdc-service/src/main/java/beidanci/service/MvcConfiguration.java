package beidanci.service;

import java.text.SimpleDateFormat;
import java.util.Locale;
import java.util.TimeZone;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.lang.NonNull;
import org.springframework.web.servlet.LocaleResolver;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
import org.springframework.web.servlet.i18n.SessionLocaleResolver;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;

@Configuration
public class MvcConfiguration implements WebMvcConfigurer {

    @Bean
    public LocaleResolver localeResolver() {
        SessionLocaleResolver slr = new SessionLocaleResolver();
        slr.setDefaultLocale(Locale.SIMPLIFIED_CHINESE);
        return slr;
    }

    /**
     * 全局配置Jackson ObjectMapper，确保所有Date类型字段序列化时带时区偏移量
     * 格式：yyyy-MM-dd'T'HH:mm:ss.SSSXXX (ISO 8601 with timezone offset)
     * 时区：GMT+8 (Asia/Shanghai)
     */
    @Bean
    @Primary
    public ObjectMapper objectMapper() {
        ObjectMapper mapper = new ObjectMapper();
        
        // 设置日期格式为ISO 8601，带时区偏移量
        SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX");
        dateFormat.setTimeZone(TimeZone.getTimeZone("GMT+8"));
        mapper.setDateFormat(dateFormat);
        
        // 设置时区（影响Date对象的序列化）
        mapper.setTimeZone(TimeZone.getTimeZone("GMT+8"));
        
        // 禁用将日期写为时间戳的功能
        mapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
        
        return mapper;
    }

    @Override
    public void addInterceptors(@NonNull InterceptorRegistry registry) {
    }

    // JDBC 不再需要 OpenSessionInViewFilter
    // @Bean
    // public OpenSessionInViewFilter openSessionInViewFilter() {
    //     return new OpenSessionInViewFilter();
    // }

}
