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
    public void testSurroundingWhitespaceTrimmed() {
        assertEquals("ˈmɪljənθ", Util.sanitizePhonetic("  ˈmɪljənθ "));
        assertEquals("ˈɜrli", Util.sanitizePhonetic("ˈɜrli "));
    }

    @Test
    public void testFullWidthBlackBracketsRemoved() {
        assertEquals("ˈkæriktəs", Util.sanitizePhonetic("【ˈkæriktəs】"));
        // 黑括号出现在音标中间时同样是包裹噪声
        assertEquals("ˈkɔntækt lenz", Util.sanitizePhonetic("ˈkɔntækt 【lenz】"));
    }

    @Test
    public void testFullWidthCommaBecomesHalfWidth() {
        assertEquals("ˈraivəl,ˈraɪvl", Util.sanitizePhonetic("ˈraivəl，ˈraɪvl"));
    }

    @Test
    public void testMisplacedLengthMarkRemoved() {
        assertEquals("ˈmæntl", Util.sanitizePhonetic("ˈmæntl:"));
        assertEquals("dɪsˈhɑrtnd", Util.sanitizePhonetic("dɪsˈhɑrtn:d"));
        assertEquals("ˌmætnˈe", Util.sanitizePhonetic("ˌmætn:ˈe"));
        assertEquals("ˈmæntl", Util.sanitizePhonetic("ˈmæntlː"));
    }

    @Test
    public void testWellPlacedLengthMarkKept() {
        // 旧式记法里长音符跟在元音后是合法的，必须原样保留
        assertEquals("ˌdisəˈɡri:", Util.sanitizePhonetic("ˌdisəˈɡri:"));
        assertEquals("ˈmɔːrnɪŋ tiː", Util.sanitizePhonetic("ˈmɔːrnɪŋ tiː"));
    }

    @Test
    public void testNullAndBlank() {
        assertNull(Util.sanitizePhonetic(null));
        assertEquals("", Util.sanitizePhonetic("   "));
    }
}
