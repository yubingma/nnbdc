package beidanci.service.bo;

import java.lang.reflect.Method;
import java.util.Map;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class DataSanitizeBoTest {

    @Test
    public void testParseChartData() throws Exception {
        DataSanitizeBo sanitizer = new DataSanitizeBo();
        Method method = DataSanitizeBo.class.getDeclaredMethod("parseChartData", String.class, String.class);
        method.setAccessible(true);

        // 模拟 book 单词的海词 HTML 内容
        String mockHtml = "<div>一些无关内容</div>" +
                "<div class=\"dict-chart\" id=\"dict-chart-basic\" data=\"%7B%221%22%3A%7B%22percent%22%3A87%2C%22sense%22%3A%22%5Cu4e66%22%7D%2C%222%22%3A%7B%22percent%22%3A11%2C%22sense%22%3A%22%5Cu9884%5Cu8ba2%22%7D%7D\"></div>" +
                "<div>其他无关内容</div>";

        String patternStr = "id=\"dict-chart-basic\"\\s+data=\"([^\"]+)\"";

        @SuppressWarnings("unchecked")
        Map<String, Object> result = (Map<String, Object>) method.invoke(sanitizer, mockHtml, patternStr);

        assertNotNull(result);
        assertEquals(2, result.size());

        // 校验 "1": {"percent": 87, "sense": "书"}
        assertTrue(result.containsKey("1"));
        Map<?, ?> item1 = (Map<?, ?>) result.get("1");
        assertEquals(87, ((Number) item1.get("percent")).intValue());
        assertEquals("书", item1.get("sense"));

        // 校验 "2": {"percent": 11, "sense": "预订"}
        assertTrue(result.containsKey("2"));
        Map<?, ?> item2 = (Map<?, ?>) result.get("2");
        assertEquals(11, ((Number) item2.get("percent")).intValue());
        assertEquals("预订", item2.get("sense"));
    }
    
    @Test
    public void testParseChartDataWithEmptyHtml() throws Exception {
        DataSanitizeBo sanitizer = new DataSanitizeBo();
        Method method = DataSanitizeBo.class.getDeclaredMethod("parseChartData", String.class, String.class);
        method.setAccessible(true);

        String mockHtml = "<div>没有图表数据的页面</div>";
        String patternStr = "id=\"dict-chart-basic\"\\s+data=\"([^\"]+)\"";

        Object result = method.invoke(sanitizer, mockHtml, patternStr);
        assertNull(result);
    }
}
