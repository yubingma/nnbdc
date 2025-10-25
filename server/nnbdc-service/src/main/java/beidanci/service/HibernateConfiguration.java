package beidanci.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.orm.hibernate5.HibernateTransactionManager;
import org.springframework.orm.hibernate5.LocalSessionFactoryBean;
import org.springframework.transaction.annotation.EnableTransactionManagement;

import javax.sql.DataSource;
import java.util.Properties;

@Configuration
@EnableTransactionManagement
public class HibernateConfiguration {
    @Value("${hibernate.dialect}")
    private String dialect;

    @Value("${hibernate.show_sql}")
    private boolean showSql;

    @Value("${hibernate.format_sql}")
    private boolean formatSql;

    @Value("${hibernate.use_sql_comments}")
    private boolean useSqlComments;

    @Value("${hibernate.hbm2ddl.auto}")
    private String ddlAuto;

    @Value("${hibernate.generate_statistics}")
    private boolean generateStatistics;

    @Value("${hibernate.packagesToScan}")
    private String packagesToScan;

    @Value("${hibernate.cache.use_second_level_cache}")
    private boolean useSecondLevelCache;

    @Value("${hibernate.cache.use_query_cache}")
    private boolean useQueryCache;

    @Autowired
    DataSource dataSource;


    @Bean
    public LocalSessionFactoryBean sessionFactory() {
        LocalSessionFactoryBean sessionFactory = new LocalSessionFactoryBean();
        sessionFactory.setDataSource(dataSource);
        sessionFactory.setPackagesToScan(packagesToScan);
        sessionFactory.setHibernateProperties(hibernateProperties());

        return sessionFactory;
    }

    private Properties hibernateProperties() {
        Properties properties = new Properties();
        properties.put("hibernate.dialect", dialect);
        properties.put("hibernate.show_sql", showSql);
        properties.put("hibernate.format_sql", formatSql);
        properties.put("hibernate.use_sql_comments", useSqlComments);
        properties.put("hibernate.hbm2ddl.auto", ddlAuto);
        properties.put("hibernate.jdbc.batch_size", 50);
        properties.put("hibernate.generate_statistics", generateStatistics);

        properties.put("hibernate.cache.use_query_cache", useQueryCache);
        properties.put("hibernate.cache.use_second_level_cache", useSecondLevelCache);
        properties.put("hibernate.cache.region.factory_class", "org.hibernate.cache.ehcache.EhCacheRegionFactory");
        properties.put("hibernate.net.sf.ehcache.configurationResourceName", "ehcache.xml");

        properties.put("hibernate.autoReconnect", true);
        return properties;
    }

    @Bean
    public HibernateTransactionManager transactionManager() {
        HibernateTransactionManager transactionManager = new HibernateTransactionManager();
        transactionManager.setSessionFactory(sessionFactory().getObject());
        return transactionManager;
    }
}
