package beidanci.service;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.data.jpa.JpaRepositoriesAutoConfiguration;
import org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration;
import org.springframework.boot.actuate.autoconfigure.security.servlet.ManagementWebSecurityAutoConfiguration;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.scheduling.annotation.EnableScheduling;

import springfox.documentation.swagger2.annotations.EnableSwagger2;

import javax.annotation.PostConstruct;
import java.util.TimeZone;


import org.springframework.scheduling.annotation.EnableAsync;

@SpringBootApplication(exclude = {
        JpaRepositoriesAutoConfiguration.class,
        // 明确禁用 Spring Security 自动配置：即使 classpath 上意外出现 security 依赖，也不启用 401/登录页等行为
        SecurityAutoConfiguration.class,
        ManagementWebSecurityAutoConfiguration.class
})
@EnableSwagger2
@EnableScheduling
@EnableAsync
@ServletComponentScan(basePackages = "beidanci.*")
public class NnbdcServiceApplication {
    @PostConstruct
    void started() {
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Shanghai"));
    }

    public static void main(String[] args) {
        SpringApplication.run(NnbdcServiceApplication.class, args);
    }


}
