package beidanci.service;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.data.jpa.JpaRepositoriesAutoConfiguration;
import org.springframework.boot.web.servlet.ServletComponentScan;
import springfox.documentation.swagger2.annotations.EnableSwagger2;


@SpringBootApplication(exclude = {JpaRepositoriesAutoConfiguration.class})
@EnableSwagger2
@ServletComponentScan(basePackages = "beidanci.*")
public class NnbdcServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(NnbdcServiceApplication.class, args);
    }


}
