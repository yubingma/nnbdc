package beidanci.service.util;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

public class UtilPhoneticTest {

    @Test
    public void testSlashWrapped() {
        assertEquals("ˈæpl", Util.sanitizePhonetic("/ˈæpl/"));
    }

    @Test
    public void testSlashWrappedWithTrailingComma() {
        assertEquals("ˈwɜːr.ʃɪ.pər", Util.sanitizePhonetic("/ˈwɜːr.ʃɪ.pər/，  "));
    }

    @Test
    public void testBracketWrapped() {
        assertEquals("nʌm", Util.sanitizePhonetic("[nʌm]"));
        assertEquals("ˈæpl", Util.sanitizePhonetic("［ˈæpl］"));
    }

    @Test
    public void testNestedWrappers() {
        // 外层方括号 + 内层斜线的多重包裹，应被循环剥离干净
        assertEquals("ˈæpl", Util.sanitizePhonetic("[/ˈæpl/]"));
    }

    @Test
    public void testStrayBackslashFromJsonEscape() {
        assertEquals("'pin,straipt", Util.sanitizePhonetic("\\'pin,straipt"));
        assertEquals("t'ræmst'ɒp", Util.sanitizePhonetic("t\\'ræmst\\'ɒp"));
    }

    @Test
    public void testBarePhoneticIsUnchanged() {
        assertEquals("ˈɔmniəm", Util.sanitizePhonetic("ˈɔmniəm"));
        assertEquals("ɔn wʌnz ɡɑ:d", Util.sanitizePhonetic("ɔn wʌnz ɡɑ:d"));
    }

    @Test
    public void testNullAndBlank() {
        assertNull(Util.sanitizePhonetic(null));
        assertEquals("", Util.sanitizePhonetic("   "));
    }
}
