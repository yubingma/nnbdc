package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 「深度讲解」批量中文翻译的取数与解析回归：模型返回的 JSON（可能带 Markdown 代码块）
 * 必须按 id 精确对应，漏答的条目不得臆造译文。
 */
public class DataSanitizeBoShortDescCnTest {

    private static final String AI_REPLY_ONE_ID = "```json\n{\"id-1\": \"某物上的瑕疵就是 defect（缺陷）。\"}\n```";

    private DataSanitizeBo buildBo(AiBo aiBo) throws Exception {
        DataSanitizeBo bo = new DataSanitizeBo();
        Field field = DataSanitizeBo.class.getDeclaredField("aiBo");
        field.setAccessible(true);
        field.set(bo, aiBo);
        return bo;
    }

    @SuppressWarnings("unchecked")
    private Map<String, String> translateBatch(DataSanitizeBo bo, List<Map<String, Object>> batch) throws Exception {
        Method method = DataSanitizeBo.class.getDeclaredMethod("translateShortDescCnBatch", List.class);
        method.setAccessible(true);
        return (Map<String, String>) method.invoke(bo, batch);
    }

    private Map<String, Object> row(String id, String spell, String shortDesc) {
        Map<String, Object> row = new HashMap<>();
        row.put("id", id);
        row.put("spell", spell);
        row.put("short_desc", shortDesc);
        return row;
    }

    private List<Map<String, Object>> twoWordBatch() {
        List<Map<String, Object>> batch = new ArrayList<>();
        batch.add(row("id-1", "defect", "A flaw in something is a defect."));
        batch.add(row("id-2", "defect", "At certain stores you can buy clothes with slight defects."));
        return batch;
    }

    @Test
    public void testBatchTranslationMapsAnswerByIdAndSendsFullText() throws Exception {
        AiBo aiBo = Mockito.mock(AiBo.class);
        when(aiBo.generateText(anyString(), anyString())).thenReturn(
                "```json\n{\"id-1\": \"某物上的瑕疵就是 defect（缺陷）。\", \"id-2\": \"在某些商店里，你可以买到略有瑕疵的衣服。\"}\n```");

        Map<String, String> translations = translateBatch(buildBo(aiBo), twoWordBatch());

        assertEquals(2, translations.size());
        assertEquals("某物上的瑕疵就是 defect（缺陷）。", translations.get("id-1"));
        assertEquals("在某些商店里，你可以买到略有瑕疵的衣服。", translations.get("id-2"));

        ArgumentCaptor<String> userPrompt = ArgumentCaptor.forClass(String.class);
        Mockito.verify(aiBo).generateText(anyString(), userPrompt.capture());
        assertTrue(userPrompt.getValue().contains("A flaw in something is a defect."));
        assertTrue(userPrompt.getValue().contains("At certain stores you can buy clothes with slight defects."));
        assertTrue(userPrompt.getValue().contains("id-2"), "必须带上 id，译文才能按条目精确对应");
    }

    @Test
    public void testMissingAnswerIsNotInvented() throws Exception {
        AiBo aiBo = Mockito.mock(AiBo.class);
        when(aiBo.generateText(anyString(), anyString())).thenReturn(AI_REPLY_ONE_ID);

        Map<String, String> translations = translateBatch(buildBo(aiBo), twoWordBatch());

        assertEquals(1, translations.size());
        assertEquals("某物上的瑕疵就是 defect（缺陷）。", translations.get("id-1"));
        assertFalse(translations.containsKey("id-2"), "模型漏答的条目不得臆造译文，应由调用方计入失败清单");
    }

    /**
     * 线上实录：有两批模型返回的 key 是单词拼写而不是 id，导致整批 15 条全部落空。
     * 取译文时必须同时接受 id 与 spell 两种 key。
     */
    @Test
    public void testPickTranslationAcceptsIdOrSpell() {
        Map<String, String> byId = new HashMap<>();
        byId.put("3625", "译文A");
        assertEquals("译文A", DataSanitizeBo.pickShortDescCn(byId, "3625", "aardvark"));

        Map<String, String> bySpell = new HashMap<>();
        bySpell.put("billfold", "译文B");
        assertEquals("译文B", DataSanitizeBo.pickShortDescCn(bySpell, "3625", "billfold"),
                "模型用拼写做 key 时同样要能取到，否则整批作废");

        Map<String, String> blank = new HashMap<>();
        blank.put("3625", "   ");
        assertNull(DataSanitizeBo.pickShortDescCn(blank, "3625", "aardvark"), "空白译文按未翻译处理");
        assertNull(DataSanitizeBo.pickShortDescCn(new HashMap<>(), "3625", "aardvark"));
    }

    /**
     * 线上实录：模型把英文原文原样返回（parenthetical 那条），若当成译文入库，
     * App 上的「译文」就会是重复的英文原文。必须判为失败，等下次重译。
     */
    @Test
    public void testEnglishEchoIsRejected() {
        Map<String, String> echoed = new HashMap<>();
        echoed.put("3625", "A parenthetical statement is one that explains or qualifies something.");

        assertNull(DataSanitizeBo.pickShortDescCn(echoed, "3625", "parenthetical"),
                "原样返回英文原文不得当成译文");
    }
}
