package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

import beidanci.api.model.WordDto;
import beidanci.service.po.Word;
import beidanci.service.util.JsonUtils;

/**
 * 端云同步契约：服务端 word 行落 sys_db_log 时用的是 WordDto 的 JSON，
 * 客户端按 key 读取（drift Word.fromJson / WordVo.fromJson 均认 "shortDescCn"）。
 * 这里锁死字段名与「整行下发」两点，避免以后改字段名或漏带该字段导致译文静默不出现在 App。
 */
public class WordDtoShortDescCnTest {

    private Word buildWord() {
        Word word = new Word();
        word.setId("0123456789abcdef0123456789abcdef");
        word.setSpell("defect");
        word.setPopularity(5);
        word.setShortDesc("A flaw in something is a defect.");
        word.setShortDescCn("某物上的瑕疵就是 defect（缺陷）。");
        word.setEnDefinition("n. an imperfection or flaw");
        word.setEmbedding1bit(new byte[] {1, 2, 3});
        return word;
    }

    @Test
    public void testToDtoCarriesShortDescCn() {
        WordDto dto = new WordBo().toDto(buildWord());

        assertTrue(dto.getShortDescCn().contains("defect"));
        assertTrue(dto.getShortDesc().startsWith("A flaw in something"));
        assertTrue(dto.getEnDefinition().contains("imperfection"));
        assertTrue(dto.getEmbedding1bit().length == 3, "整行下发必须带向量，否则客户端本地向量被刷空");
    }

    @Test
    public void testSyncLogJsonUsesShortDescCnKey() {
        String json = JsonUtils.toJson(new WordBo().toDto(buildWord()));

        assertTrue(json.contains("\"shortDescCn\""), "客户端按 shortDescCn 读取，字段名不得改");
        assertTrue(json.contains("\"enDefinition\""), "客户端按 enDefinition 读取，字段名不得改");
        assertTrue(json.contains("某物上的瑕疵就是 defect（缺陷）。"));
        assertFalse(json.contains("short_desc_cn"), "下发 JSON 用驼峰，不得泄漏数据库列名");
        assertFalse(json.contains("en_definition"), "下发 JSON 用驼峰，不得泄漏数据库列名");
    }
}
