package beidanci.service.config;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;

import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.bind.Bindable;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.context.properties.bind.PropertySourcesPlaceholdersResolver;
import org.springframework.boot.context.properties.source.ConfigurationPropertySources;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.MutablePropertySources;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.ClassPathResource;

/**
 * 配图 CDN 地址前缀的绑定测试。
 *
 * 这个配置决定「删除配图后要去刷新哪个 CDN 地址」。如果 application.yml 里的键名和
 * {@link AliyunCdnProperties} 的字段对不上，运行时拿到的是 null，而那一刻图片文件已经删掉、
 * 数据库事务还要回滚，现场会变得很乱。所以这里把真实的 application.yml 绑一遍，确保键名始终对得上。
 */
public class AliyunCdnPropertiesTest {

    @Test
    public void testImageBaseUrlBoundFromApplicationYml() throws Exception {
        MutablePropertySources sources = new MutablePropertySources();
        List<PropertySource<?>> yamlSources = new YamlPropertySourceLoader()
                .load("application", new ClassPathResource("application.yml"));
        yamlSources.forEach(sources::addLast);

        Binder binder = new Binder(ConfigurationPropertySources.from(sources),
                new PropertySourcesPlaceholdersResolver(sources));
        AliyunCdnProperties properties = binder.bind("aliyun.cdn", Bindable.of(AliyunCdnProperties.class))
                .orElseGet(AliyunCdnProperties::new);

        assertNotNull(properties.getImageBaseUrl(),
                "application.yml 的 aliyun.cdn.image-base-url 没有绑定到 AliyunCdnProperties.imageBaseUrl");
        assertTrue(properties.getImageBaseUrl().endsWith("/img/"),
                "配图地址前缀应以 /img/ 结尾，实际绑定到: " + properties.getImageBaseUrl());
    }
}
