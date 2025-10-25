package beidanci.service;

import java.util.Date;

/**
 * 线程上下文，当前线程的变量以ThreadLocal存放在其中。当跨越Hystrix线程边界时，ThreadLocal变量会自动传递
 */
public class ThreadContext {
    private static final ThreadLocal<ContextData> dataHolder = new ThreadLocal<>();

    public static ContextData getData() {
        ContextData data = dataHolder.get();
        if (data == null) {
            data = new ContextData();
            dataHolder.set(data);
        }
        return data;
    }

    public static void setData(ContextData data) {
        dataHolder.set(data);
    }

    public static Date getStartTime() {
        return getData().getStartTime();
    }

    public static void setStartTime(Date startTime) {
        getData().setStartTime(startTime);
    }

    public static Date getEndTime() {
        return getData().getEndTime();
    }

    public static void setEndTime(Date startTime) {
        getData().setEndTime(startTime);
    }

}
