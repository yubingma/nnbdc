package beidanci.service.util;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

public class UtilAbbreviationTest {

    @Test
    public void testStandaloneAbbreviations() {
        assertEquals("get on with something", Util.toSpokenEnglish("get on with sth"));
        assertEquals("be in love with somebody.", Util.toSpokenEnglish("be in love with sb."));
        assertEquals("take the trouble to do something.", Util.toSpokenEnglish("take the trouble to do sth."));
    }

    @Test
    public void testSlashPairReadsAsOr() {
        assertEquals("let out somebody or something", Util.toSpokenEnglish("let out sb/sth"));
        assertEquals("let out somebody or something", Util.toSpokenEnglish("let out sb./sth."));
        // 逆序写法同样处理
        assertEquals("something or somebody", Util.toSpokenEnglish("sth/sb"));
    }

    @Test
    public void testPossessive() {
        assertEquals("somebody's help", Util.toSpokenEnglish("sb's help"));
        assertEquals("something's wrong", Util.toSpokenEnglish("sth's wrong"));
    }

    @Test
    public void testCaseInsensitive() {
        assertEquals("somebody test", Util.toSpokenEnglish("SB test"));
        assertEquals("somebody or something", Util.toSpokenEnglish("SB/STH"));
    }

    @Test
    public void testOtherSlashesUntouched() {
        // 只处理约定缩写，其它斜线必须原样保留
        assertEquals("km/h and/or he or she", Util.toSpokenEnglish("km/h and/or he or she"));
    }

    @Test
    public void testWordBoundary() {
        // 不能误伤包含 sb/sth 字母序列的普通单词
        assertEquals("absolutely asthma", Util.toSpokenEnglish("absolutely asthma"));
    }

    @Test
    public void testNullAndBlank() {
        assertNull(Util.toSpokenEnglish(null));
        assertEquals("", Util.toSpokenEnglish(""));
    }

    @Test
    public void testHasEnglishAbbreviation() {
        assertTrue(Util.hasEnglishAbbreviation("get on with sth"));
        assertTrue(Util.hasEnglishAbbreviation("sb/sth"));
        assertFalse(Util.hasEnglishAbbreviation("absolutely asthma"));
        assertFalse(Util.hasEnglishAbbreviation(null));
    }
}
