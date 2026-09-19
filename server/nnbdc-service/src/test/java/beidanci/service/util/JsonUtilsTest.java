package beidanci.service.util;

import java.util.Map;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import beidanci.service.bo.WordCoreImageBo;

public class JsonUtilsTest {

    @Test
    public void testRepairAiJson_doesNotInjectCommasOnStandardJson() {
        String input = "{\n"
                + "  \"is_applicable\": true,\n"
                + "  \"core_image\": \"偏执乱用强加\",\n"
                + "  \"schema_desc\": \"把本该好好用的东西偏向坏处粗暴乱用。用在人身上是施虐，用在言语上是辱骂。\",\n"
                + "  \"branches\": [\n"
                + "    {\n"
                + "      \"pos\": \"n.\",\n"
                + "      \"meaning\": \"施虐者，滥用者\",\n"
                + "      \"relation\": \"偏向坏处加力于人\",\n"
                + "      \"desc\": \"把力量偏向受害人\"\n"
                + "    }\n"
                + "  ]\n"
                + "}";

        Map<String, Object> map = JsonUtils.parseAiMap(input);
        assertNotNull(map);
        assertEquals("偏执乱用强加", map.get("core_image"));
        assertFalse(((String) map.get("core_image")).contains("，"));
        assertFalse(((String) map.get("schema_desc")).endsWith("，"));
        assertFalse(((String) map.get("schema_desc")).endsWith(","));
    }

    @Test
    public void testCleanPunctuation() {
        assertEquals("偏执施力于对象", WordCoreImageBo.cleanPunctuation("偏执施力于对象， ， "));
        assertEquals("施虐者，滥用者", WordCoreImageBo.cleanPunctuation("施虐者，滥用者， "));
        assertEquals("n.", WordCoreImageBo.cleanPunctuation("n.， "));
        assertEquals("abc", WordCoreImageBo.cleanPunctuation("，； abc；， "));
    }
}
