package beidanci.service;

import java.util.Locale;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.lang.NonNull;
import org.springframework.web.servlet.LocaleResolver;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
import org.springframework.web.servlet.i18n.SessionLocaleResolver;

@Configuration
public class MvcConfiguration implements WebMvcConfigurer {

    @Bean
    public LocaleResolver localeResolver() {
        SessionLocaleResolver slr = new SessionLocaleResolver();
        slr.setDefaultLocale(Locale.SIMPLIFIED_CHINESE);
        return slr;
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
