package beidanci.service.log;

import ch.qos.logback.classic.pattern.ThrowableProxyConverter;
import ch.qos.logback.classic.spi.IThrowableProxy;
import ch.qos.logback.core.CoreConstants;

/**
 * 自定义异常堆栈转换器，高亮显示包含beidanci字样的行
 */
public class BeidanciStackTraceConverter extends ThrowableProxyConverter {

    // ANSI颜色代码
    private static final String ANSI_RESET = "\u001B[0m";
    private static final String ANSI_BRIGHT_GREEN = "\u001B[92m";

    @Override
    protected String throwableProxyToString(IThrowableProxy tp) {
        // 获取原始堆栈信息
        String stackTrace = super.throwableProxyToString(tp);
        if (stackTrace == null) {
            return null;
        }

        // 按行分割堆栈信息
        String[] lines = stackTrace.split(CoreConstants.LINE_SEPARATOR);
        StringBuilder builder = new StringBuilder();

        // 处理每一行，高亮包含beidanci的行
        for (String line : lines) {
            if (line.contains("beidanci")) {
                builder.append(ANSI_BRIGHT_GREEN).append(line).append(ANSI_RESET);
            } else {
                builder.append(line);
            }
            builder.append(CoreConstants.LINE_SEPARATOR);
        }

        return builder.toString();
    }
}
