package beidanci.service.util;

import java.io.IOException;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.servlet.http.HttpServletResponse;

import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.annotation.JsonInclude.Include;
import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.JsonGenerator;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;

public class JsonUtils {
    private static final Logger logger = LoggerFactory.getLogger(JsonUtils.class);

    /**
     * 把数据对象直接格式化为JSON字符串发送出去
     *
     * @param data
     * @throws IOException
     */
    public static String sendJson(Object data, HttpServletResponse response) throws IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("utf-8");
        PrintWriter out = response.getWriter();
        String json = toJson(data);
        out.print(json);
        return json;
    }

    public static String toJson(Object data) {
        ObjectMapper mapper = new ObjectMapper();
        mapper.setSerializationInclusion(Include.NON_NULL);
        mapper.configure(SerializationFeature.WRITE_ENUMS_USING_TO_STRING, true);
        mapper.configure(SerializationFeature.FAIL_ON_EMPTY_BEANS, false);
        StringWriter sw = new StringWriter();
        JsonGenerator gen;
        try {
            gen = new JsonFactory().createGenerator(sw);
            mapper.writeValue(gen, data);
            gen.close();
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
        return sw.toString();
    }

    public static <T> T makeObject(String json, Class<T> clazz) {
        if (StringUtils.isBlank(json)) {
            return null;
        }

        ObjectMapper mapper = new ObjectMapper();
        mapper.setSerializationInclusion(Include.NON_NULL);
        mapper.configure(SerializationFeature.WRITE_ENUMS_USING_TO_STRING, true);
        mapper.configure(SerializationFeature.FAIL_ON_EMPTY_BEANS, false);
        // 允许JSON包含实体类没有的属性
        mapper.configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
        try {
            return mapper.readValue(json, clazz);
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

    @SuppressWarnings("unchecked")
    public static Map<String, Object> parseMap(String json) {
        if (StringUtils.isBlank(json)) {
            return new HashMap<>();
        }
        return makeObject(json, Map.class);
    }

    /**
     * 专门用于解析 AI 生成的 JSON 字符串。
     * 包含提取 JSON 块、修复常见错误（如 unquoted text、缺失逗号等）的逻辑。
     * @param aiOutput AI 的原始输出文本
     * @return 解析后的 Map
     */
    public static Map<String, Object> parseAiMap(String aiOutput) {
        if (StringUtils.isBlank(aiOutput)) {
            return new HashMap<>();
        }

        String repairedJson = repairAiJson(aiOutput);
        try {
            return parseMap(repairedJson);
        } catch (Exception e) {
            logger.error("Failed to parse AI JSON even after repair. Original: {}, Repaired: {}", aiOutput, repairedJson, e);
            throw e;
        }
    }

    /**
     * 修复 AI 生成的 JSON 中常见的格式错误
     */
    public static String repairAiJson(String json) {
        if (json == null) return null;

        // 1. 清理 Markdown 代码块
        json = json.replaceAll("^```(?:json)?\\s*", "").replaceAll("\\s*```$", "").trim();

        // 2. 提取第一个 { ... } 或 [ ... ] 块
        int firstBrace = json.indexOf('{');
        int firstBracket = json.indexOf('[');
        int start = -1;
        if (firstBrace >= 0 && firstBracket >= 0) start = Math.min(firstBrace, firstBracket);
        else if (firstBrace >= 0) start = firstBrace;
        else if (firstBracket >= 0) start = firstBracket;

        if (start >= 0) {
            int end = (json.charAt(start) == '{') ? json.lastIndexOf('}') : json.lastIndexOf(']');
            if (end > start) {
                json = json.substring(start, end + 1);
            }
        }

        String original = json;

        // 3. 修复 unquoted text 紧跟在字符串值之后的情况 (如 "meaning": "xxx", <b>...</b> "sentenceCn": ...)
        // 这种情况下，AI 往往是把一部分内容漏在了引号外面。我们将这部分内容合并进前一个引号内。
        // 正则：查找 引号+逗号+空白 + (非引号非冒号非括号非逗号的内容) + 空白 + 引号 + (键名) + 引号 + 冒号
        Pattern p1 = Pattern.compile("(?s)\",\\s*([^\"\\{}\\],:]+?)\\s*\"([^\"]+)\"\\s*:");
        Matcher m1 = p1.matcher(json);
        if (m1.find()) {
            json = m1.replaceAll("， $1\", \"$2\":");
        }

        // 4. 修复缺失逗号的情况: "field1": "val1" "field2": "val2"
        Pattern p2 = Pattern.compile("(?s)\"\\s+\"([^\"]+)\"\\s*:");
        Matcher m2 = p2.matcher(json);
        if (m2.find()) {
            json = m2.replaceAll("\", \"$1\":");
        }

        // 5. 修复末尾多余的逗号: [1, 2, ] 或 {"a":1, }
        json = json.replaceAll(",\\s*([}\\]])", "$1");

        if (!json.equals(original)) {
            logger.warn("Repaired AI JSON. Before: {}, After: {}", original, json);
        }

        return json;
    }
}
