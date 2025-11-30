package beidanci.service.util;

import com.p6spy.engine.spy.appender.MultiLineFormat;
// JDBC 不再使用 Hibernate 的 SQL 格式化器
// import org.hibernate.engine.jdbc.internal.BasicFormatterImpl;
// import org.hibernate.engine.jdbc.internal.Formatter;


public class PrettySqlMultiLineFormat extends MultiLineFormat {
    // JDBC 不再使用 Hibernate 的 SQL 格式化器，直接返回原始 SQL
    // private static final Formatter FORMATTER = new BasicFormatterImpl();

    @Override
    public String formatMessage(int connectionId, String now, long elapsed, String category, String prepared, String sql) {
        // JDBC 不再格式化 SQL，直接返回原始 SQL
        return super.formatMessage(connectionId, now, elapsed, category, prepared, sql);
        // return super.formatMessage(connectionId, now, elapsed, category, FORMATTER.format(prepared), FORMATTER.format(sql));
    }
}
