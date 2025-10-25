package beidanci.service.config;

import java.util.ArrayList;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import beidanci.api.SortType;
import beidanci.api.model.ClientType;
import beidanci.api.model.CheckBy;
import beidanci.api.model.MsgType;
import springfox.documentation.builders.PathSelectors;
import springfox.documentation.builders.RequestHandlerSelectors;
import springfox.documentation.service.ApiInfo;
import springfox.documentation.service.Contact;
import springfox.documentation.spi.DocumentationType;
import springfox.documentation.spring.web.plugins.Docket;
import springfox.documentation.swagger2.annotations.EnableSwagger2;

@Configuration
@EnableSwagger2
public class SwaggerConfig {

    @Bean
    public Docket api() {
        return new Docket(DocumentationType.SWAGGER_2)
                .select()
                .apis(RequestHandlerSelectors.any())
                .paths(PathSelectors.any())
                .build()
                .apiInfo(apiInfo())
                .useDefaultResponseMessages(false)
                .directModelSubstitute(CheckBy.class, String.class)
                .directModelSubstitute(ClientType.class, String.class)
                .directModelSubstitute(MsgType.class, String.class)
                .directModelSubstitute(SortType.class, String.class);
    }

    private ApiInfo apiInfo() {
        return new ApiInfo(
                "背单词 API",
                "背单词应用API文档",
                "API V1.0",
                "Terms of service",
                new Contact("NNBDC", "www.nnbdc.com", "support@nnbdc.com"),
                "License of API", "API license URL", new ArrayList<>());
    }
}
