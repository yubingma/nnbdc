package beidanci.service.util;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.time.LocalDate;
import java.util.Calendar;
import java.util.Date;
import java.util.TimeZone;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import beidanci.util.Utils;

/**
 * 服务端"业务日期"（凌晨 3 点切日）语义测试。
 *
 * <p>客户端 {@code DateUtils.businessDate} 的规则是：瞬时按本地墙钟判定，00:00~02:59 归前一天，03:00 起归当天。
 * 服务端在"当前是哪一天"的所有判定上必须采用同一规则，否则凌晨 0~3 点会与客户端结论不一致，
 * 小组"今日打卡人数"、连续打卡天数、打卡率分母都会随之出错。
 */
public class UtilsBusinessDateTest {

    @BeforeAll
    static void fixTimeZone() {
        // 与 NnbdcServiceApplication#started 启动时固定的时区保持一致
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Shanghai"));
    }

    private static Date at(int year, int month, int day, int hour, int minute) {
        Calendar c = Calendar.getInstance();
        c.clear();
        c.set(year, month - 1, day, hour, minute, 0);
        return c.getTime();
    }

    private static LocalDate businessDate(int year, int month, int day, int hour, int minute) {
        return Utils.getBusinessDate(at(year, month, day, hour, minute));
    }

    @Test
    @DisplayName("凌晨 3 点是业务日切换界：02:59 归前一天，03:00 归当天")
    void testThreeAmCutoff() {
        assertEquals(LocalDate.of(2026, 5, 10), businessDate(2026, 5, 11, 2, 59));
        assertEquals(LocalDate.of(2026, 5, 10), businessDate(2026, 5, 11, 0, 0));
        assertEquals(LocalDate.of(2026, 5, 11), businessDate(2026, 5, 11, 3, 0));
        assertEquals(LocalDate.of(2026, 5, 11), businessDate(2026, 5, 11, 23, 59));
    }

    @Test
    @DisplayName("跨月与跨年：日历回退必须自动进位")
    void testMonthAndYearRollover() {
        assertEquals(LocalDate.of(2026, 4, 30), businessDate(2026, 5, 1, 1, 30));
        assertEquals(LocalDate.of(2025, 12, 31), businessDate(2026, 1, 1, 1, 30));
        assertEquals(LocalDate.of(2026, 1, 1), businessDate(2026, 1, 1, 3, 0));
    }

    @Test
    @DisplayName("夜猫子：次日 01:30 与前一天白天属于同一业务日，过 3 点才进入新业务日")
    void testNightOwlSameBusinessDay() {
        assertEquals(
                Utils.getBusinessDate(at(2026, 5, 10, 22, 30)),
                Utils.getBusinessDate(at(2026, 5, 11, 1, 30)));
        assertEquals(LocalDate.of(2026, 5, 11), businessDate(2026, 5, 11, 3, 15));
    }

    @Test
    @DisplayName("今日打卡查询键必须命中客户端持久化的业务日 0 点瞬时")
    void testLookupKeyMatchesClientPersistedKey() {
        // 客户端在业务日 2026-05-10 打卡，落库的 for_learning_date 就是上海 5/10 00:00
        Date clientPersistedKey = at(2026, 5, 10, 0, 0);
        // 服务端在 5/11 01:30 判定"今天是否打卡"，必须查 5/10 这个键，而不是 5/11
        Date serverLookupKey = Utils.localDate2Date(Utils.getBusinessDate(at(2026, 5, 11, 1, 30)));
        assertEquals(clientPersistedKey, serverLookupKey);
    }

    @Test
    @DisplayName("getPureDate 仍然只做自然日截断，不得被业务日规则污染")
    void testPureDateUnaffectedByBusinessDayRule() {
        // 已归一化的业务日数据（凌晨 0 点）再走 getPureDate 必须保持原样，绝不能被前移一天
        assertEquals(at(2026, 5, 10, 0, 0), Utils.getPureDate(at(2026, 5, 10, 0, 0)));
        assertEquals(at(2026, 5, 11, 0, 0), Utils.getPureDate(at(2026, 5, 11, 2, 59)));
    }
}
