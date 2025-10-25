package beidanci.service.security;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.password.PasswordEncoder;

public class ConfigurablePasswordEncoder implements PasswordEncoder {

    private final Logger logger = LoggerFactory.getLogger(getClass());

    private final EncodingAlgorithm encodingAlgorithm;

    public ConfigurablePasswordEncoder(EncodingAlgorithm encodingAlgorithm) {
        this.encodingAlgorithm = encodingAlgorithm;
    }

    @Override
    public String encode(CharSequence rawPassword) {
        return EncodingUtils.encode(rawPassword.toString(), encodingAlgorithm);
    }

    @Override
    public boolean matches(CharSequence rawPassword, String encodedPassword) {
        if (encodedPassword == null || encodedPassword.length() == 0) {
            logger.warn("Empty encoded password");
            return false;
        }

        return this.encode(rawPassword).equals(encodedPassword);
    }
}
