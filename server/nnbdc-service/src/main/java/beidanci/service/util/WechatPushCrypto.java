package beidanci.service.util;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import java.util.Base64;

import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * 微信开放平台「消息推送」的验签与报文解密。
 *
 * 规范: https://developers.weixin.qq.com/doc/oplatform/Mobile_App/WeChat_Login/message_push.html
 * 加解密算法与公众号/小程序一致: AES-256-CBC + PKCS#7，解密后明文为
 * random(16B) + msg_len(4B, 网络字节序) + msg + appid。
 */
public class WechatPushCrypto {

    private WechatPushCrypto() {
    }

    /**
     * 校验 URL 验证（GET）以及明文模式推送的 signature: sha1(sort(token, timestamp, nonce))。
     */
    public static boolean verifyUrlSignature(String token, String timestamp, String nonce, String signature) {
        return matches(sha1Hex(token, timestamp, nonce), signature);
    }

    /**
     * 校验安全模式推送的 msg_signature: sha1(sort(token, timestamp, nonce, encrypt))。
     *
     * 注意: 安全模式必须用本方法，不要用 URL 上的 signature。
     */
    public static boolean verifyMsgSignature(String token, String timestamp, String nonce, String encrypt,
            String msgSignature) {
        return matches(sha1Hex(token, timestamp, nonce, encrypt), msgSignature);
    }

    /**
     * 解密安全模式推送报文中的 Encrypt 密文。
     *
     * @param encodingAesKey 开放平台配置的 EncodingAESKey（43 位）
     * @param encrypt        报文中的 Encrypt 字段（Base64 密文）
     * @param expectedAppId  本应用的 AppID，用于校验密文确实是发给自己的；传 null 或空串则跳过校验
     * @return 解密后的事件明文（JSON）
     */
    public static String decrypt(String encodingAesKey, String encrypt, String expectedAppId) {
        byte[] aesKey = Base64.getDecoder().decode(encodingAesKey + "=");
        if (aesKey.length != 32) {
            throw new IllegalArgumentException("EncodingAESKey 解码后应为 32 字节，实际为 " + aesKey.length + " 字节");
        }

        byte[] plain;
        try {
            Cipher cipher = Cipher.getInstance("AES/CBC/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(aesKey, "AES"),
                    new IvParameterSpec(Arrays.copyOf(aesKey, 16)));
            plain = removePkcs7Padding(cipher.doFinal(Base64.getDecoder().decode(encrypt)));
        } catch (GeneralSecurityException e) {
            throw new IllegalArgumentException("微信推送报文解密失败: " + e.getMessage(), e);
        }

        if (plain.length < 20) {
            throw new IllegalArgumentException("微信推送报文解密结果过短: " + plain.length + " 字节");
        }

        int msgLength = ((plain[16] & 0xFF) << 24) | ((plain[17] & 0xFF) << 16) | ((plain[18] & 0xFF) << 8)
                | (plain[19] & 0xFF);
        if (msgLength < 0 || 20 + msgLength > plain.length) {
            throw new IllegalArgumentException(
                    "微信推送报文声明的消息长度为 " + msgLength + "，超出解密结果长度 " + plain.length);
        }

        String receiverAppId = new String(plain, 20 + msgLength, plain.length - 20 - msgLength,
                StandardCharsets.UTF_8);
        if (expectedAppId != null && !expectedAppId.isEmpty() && !expectedAppId.equals(receiverAppId)) {
            throw new IllegalArgumentException("微信推送报文的接收方 AppID 为 " + receiverAppId + "，与本应用不符");
        }

        return new String(plain, 20, msgLength, StandardCharsets.UTF_8);
    }

    private static byte[] removePkcs7Padding(byte[] data) {
        if (data.length == 0) {
            throw new IllegalArgumentException("微信推送报文解密结果为空");
        }
        int pad = data[data.length - 1] & 0xFF;
        if (pad < 1 || pad > 32 || pad > data.length) {
            throw new IllegalArgumentException("非法的 PKCS#7 填充长度: " + pad);
        }
        for (int i = data.length - pad; i < data.length; i++) {
            if ((data[i] & 0xFF) != pad) {
                throw new IllegalArgumentException("非法的 PKCS#7 填充内容");
            }
        }
        return Arrays.copyOf(data, data.length - pad);
    }

    private static String sha1Hex(String... parts) {
        String[] sorted = parts.clone();
        Arrays.sort(sorted);

        byte[] hash;
        try {
            hash = MessageDigest.getInstance("SHA-1").digest(String.join("", sorted).getBytes(StandardCharsets.UTF_8));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("JVM 不支持 SHA-1 算法", e);
        }

        StringBuilder hex = new StringBuilder(hash.length * 2);
        for (byte b : hash) {
            hex.append(Character.forDigit((b >> 4) & 0xF, 16)).append(Character.forDigit(b & 0xF, 16));
        }
        return hex.toString();
    }

    private static boolean matches(String expected, String actual) {
        return actual != null && MessageDigest.isEqual(expected.getBytes(StandardCharsets.UTF_8),
                actual.getBytes(StandardCharsets.UTF_8));
    }
}
