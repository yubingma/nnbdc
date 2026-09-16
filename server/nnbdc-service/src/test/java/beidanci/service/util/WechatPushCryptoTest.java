package beidanci.service.util;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

/**
 * 测试向量全部取自微信官方文档《消息推送》的示例，
 * 用于保证验签与解密实现与微信协议严格一致。
 */
public class WechatPushCryptoTest {

    private static final String TOKEN = "AAAAA";
    private static final String ENCODING_AES_KEY = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    private static final String APP_ID = "wxba5fad812f8e6fb9";

    private static final String ENCRYPT = "+qdx1OKCy+5JPCBFWw70tm0fJGb2Jmeia4FCB7kao+/Q5c/ohsOzQHi8khUOb05JCpj0JB4RvQMkUyus8TPxLKJGQqcvZqzDpVzazhZv6JsXUnnR8XGT740XgXZUXQ7vJVnAG+tE8NUd4yFyjPy7GgiaviNrlCTj+l5kdfMuFUPpRSrfMZuMcp3Fn2Pede2IuQrKEYwKSqFIZoNqJ4M8EajAsjLY2km32IIjdf8YL/P50F7mStwntrA2cPDrM1kb6mOcfBgRtWygb3VIYnSeOBrebufAlr7F9mFUPAJGj04=";
    private static final String MSG_SIGNATURE = "046e02f8204d34f8ba5fa3b1db94908f3df2e9b3";
    private static final String MESSAGE = "{\"ToUserName\":\"gh_97417a04a28d\",\"FromUserName\":\"o9AgO5Kd5ggOC-bXrbNODIiE3bGY\",\"CreateTime\":1714112445,\"MsgType\":\"event\",\"Event\":\"debug_demo\",\"debug_str\":\"hello world\"}";

    @Test
    public void testVerifyUrlSignature() {
        assertTrue(WechatPushCrypto.verifyUrlSignature(TOKEN, "1714036504", "1514711492",
                "f464b24fc39322e44b38aa78f5edd27bd1441696"));
        assertTrue(WechatPushCrypto.verifyUrlSignature(TOKEN, "1714037059", "486452656",
                "899cf89e464efb63f54ddac96b0a0a235f53aa78"));
    }

    @Test
    public void testVerifyUrlSignatureRejectsWrongSignature() {
        assertFalse(WechatPushCrypto.verifyUrlSignature(TOKEN, "1714036504", "1514711492",
                "899cf89e464efb63f54ddac96b0a0a235f53aa78"));
        assertFalse(WechatPushCrypto.verifyUrlSignature("WRONG", "1714036504", "1514711492",
                "f464b24fc39322e44b38aa78f5edd27bd1441696"));
        assertFalse(WechatPushCrypto.verifyUrlSignature(TOKEN, "1714036504", "1514711492", null));
    }

    @Test
    public void testVerifyMsgSignature() {
        assertTrue(WechatPushCrypto.verifyMsgSignature(TOKEN, "1714112445", "415670741", ENCRYPT, MSG_SIGNATURE));
    }

    @Test
    public void testVerifyMsgSignatureRejectsWrongSignature() {
        assertFalse(WechatPushCrypto.verifyMsgSignature(TOKEN, "1714112445", "415670741", ENCRYPT,
                "f464b24fc39322e44b38aa78f5edd27bd1441696"));
    }

    @Test
    public void testDecrypt() {
        assertEquals(MESSAGE, WechatPushCrypto.decrypt(ENCODING_AES_KEY, ENCRYPT, APP_ID));
    }

    @Test
    public void testDecryptRejectsWrongAppId() {
        assertThrows(IllegalArgumentException.class,
                () -> WechatPushCrypto.decrypt(ENCODING_AES_KEY, ENCRYPT, "wx0000000000000000"));
    }

    @Test
    public void testDecryptRejectsWrongAesKey() {
        assertThrows(IllegalArgumentException.class,
                () -> WechatPushCrypto.decrypt("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", ENCRYPT, APP_ID));
    }
}
