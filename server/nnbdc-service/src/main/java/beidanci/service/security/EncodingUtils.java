package beidanci.service.security;

import org.apache.commons.codec.digest.DigestUtils;

public class EncodingUtils {

    public static String encode(String plainText, EncodingAlgorithm alg) {
        String encodedText;

        if (alg == null) {
            encodedText = plainText;
        } else {
            encodedText = encode(plainText, alg.getValue());
        }

        return encodedText;
    }

    public static String encode(String plainText, String alg) {
        String encodedText;

        if (EncodingAlgorithm.MD5.getValue().equals(alg)) {
            encodedText = DigestUtils.md5Hex(plainText);
        } else if (EncodingAlgorithm.SHA1.getValue().equals(alg)) {
            encodedText = DigestUtils.sha1Hex(plainText);
        } else if (EncodingAlgorithm.SHA256.getValue().equals(alg)) {
            encodedText = DigestUtils.sha256Hex(plainText);
        } else {
            encodedText = plainText;
        }

        return encodedText;
    }
}
