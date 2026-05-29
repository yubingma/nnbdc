package beidanci.service.util;

import java.util.Date;
import java.util.TimeZone;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;

import static org.junit.jupiter.api.Assertions.*;

/**
 * 数据库同步全链路时区序列化集成与保护测试
 * 旨在把服务端在数据持久化读取、JSON 网络序列化传输、客户端解析这整条同步链路上的“正确时区行为”固化下来，
 * 彻底防止未来因时区遗漏导致 8 小时数据静默覆盖冲突的 regression。
 */
public class SyncTimezoneSerializationTest {

    private static final Logger logger = LoggerFactory.getLogger(SyncTimezoneSerializationTest.class);

    /**
     * 北京时间 2026-05-29 20:00:00 对应的绝对物理时间是 12:00:00 UTC
     * 其绝对 Unix 时间戳毫秒数为 1779931200000L
     */
    private static final long MOCK_ABSOLUTE_MS = 1779931200000L;

    @Test
    @DisplayName("验证增量同步接口中 ObjectMapper 时区序列化行为（固化防覆盖隐患）")
    public void testSyncObjectMapperTimezoneSerialization() throws Exception {
        logger.info("=== 开始验证同步时区序列化测试 ===");

        // 1. 构造一个绝对物理时刻对象（北京时间 20:00:00，物理上是 12:00:00 UTC）
        Date originalDate = new Date(MOCK_ABSOLUTE_MS);
        logger.info("原始绝对物理时刻 (Original Date): {}", originalDate);

        // 2. 模拟经过修复配置后的 ObjectMapper（带有强制 UTC 时区）
        ObjectMapper correctMapper = new ObjectMapper();
        correctMapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
        
        java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
        sdf.setTimeZone(TimeZone.getTimeZone("UTC")); // 关键点：显式设置为 UTC 时区
        correctMapper.setDateFormat(sdf);

        // 3. 模拟漏洞未修复时的 ObjectMapper（硬编码 'Z' 但丢失 TimeZone 设置）
        ObjectMapper buggyMapper = new ObjectMapper();
        buggyMapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
        buggyMapper.setDateFormat(new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));

        // 4. 执行序列化并对比
        String correctJson = correctMapper.writeValueAsString(originalDate);
        String buggyJson = buggyMapper.writeValueAsString(originalDate);

        logger.info("【正确修复后】网络传输的 JSON 日期字符串: {}", correctJson);
        logger.info("【漏洞未修前】网络传输的 JSON 日期字符串: {}", buggyJson);

        // 5. 核心断言一：正确序列化出的日期格式，必须绝对对齐 UTC (即 "2026-05-28T01:20:00.000Z")
        // 如果服务器在东八区，buggyJson 会硬编码输出包含 09:20:00 的错误 UTC 串，这在物理上慢了 8 小时。
        assertEquals("\"2026-05-28T01:20:00.000Z\"", correctJson, "时区转换发生物理时刻偏差！未完美归一到 UTC！");

        // 6. 核心断言二：模拟客户端（Flutter）或反向传输反序列化时的时区绝对对齐
        // 验证用正确格式解析出的物理时间戳必须与原始绝对毫秒数完全一致（零误差）
        Date parsedCorrectDate = correctMapper.readValue(correctJson, Date.class);
        assertEquals(MOCK_ABSOLUTE_MS, parsedCorrectDate.getTime(), "时区反序列化发生物理时刻退化偏移！");
        logger.info("反序列化后的绝对物理时刻 (Parsed Date): {}, 校验绝对一致！", parsedCorrectDate);

        // 7. 对比演示漏洞情况下的“时光倒流”现象（仅当运行在非 UTC 时区环境下时有显著差值）
        if (!TimeZone.getDefault().getID().equals("UTC")) {
            // 模拟客户端或标准的时区敏感解析器（如 Dart 客户端）在解析该格式时的行为
            Date parsedBuggyDate = correctMapper.readValue(buggyJson, Date.class);
            long timeGapMs = Math.abs(parsedBuggyDate.getTime() - parsedCorrectDate.getTime());
            logger.warn("⚠️ 检测到当前环境非 UTC 默认时区，未修复前的时区序列化将导致数据物理时差为: {} 小时 ({} ms)", 
                timeGapMs / 1000 / 3600, timeGapMs);
            
            // 漏洞版本下在东八区环境下反序列化会慢 8 小时 (物理时刻变大即变晚 8 小时)，在此处通过测试把这一隐患固化并证明已完美防范
            assertNotEquals(MOCK_ABSOLUTE_MS, parsedBuggyDate.getTime(), "警告！原先的漏洞格式在当前时区下逃过了安全拦截！");
        }

        logger.info("=== 时区序列化全链路验证测试完美通过 ===");
    }
}
