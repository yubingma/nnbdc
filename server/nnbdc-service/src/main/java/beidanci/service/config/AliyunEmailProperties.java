package beidanci.service.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "aliyun.email")
public class AliyunEmailProperties {

    private String accessKeyId;
    private String accessKeySecret;
    private String regionId;
    private String fromAddress;
    private String fromAlias;
    private TemplateIds templateIds = new TemplateIds();

    public String getAccessKeyId() {
        return accessKeyId;
    }

    public void setAccessKeyId(String accessKeyId) {
        this.accessKeyId = accessKeyId;
    }

    public String getAccessKeySecret() {
        return accessKeySecret;
    }

    public void setAccessKeySecret(String accessKeySecret) {
        this.accessKeySecret = accessKeySecret;
    }

    public String getRegionId() {
        return regionId;
    }

    public void setRegionId(String regionId) {
        this.regionId = regionId;
    }

    public String getFromAddress() {
        return fromAddress;
    }

    public void setFromAddress(String fromAddress) {
        this.fromAddress = fromAddress;
    }

    public String getFromAlias() {
        return fromAlias;
    }

    public void setFromAlias(String fromAlias) {
        this.fromAlias = fromAlias;
    }

    public TemplateIds getTemplateIds() {
        return templateIds;
    }

    public void setTemplateIds(TemplateIds templateIds) {
        this.templateIds = templateIds;
    }

    public static class TemplateIds {
        private String verificationCode;
        private String getPassword;

        public String getVerificationCode() {
            return verificationCode;
        }

        public void setVerificationCode(String verificationCode) {
            this.verificationCode = verificationCode;
        }

        public String getGetPassword() {
            return getPassword;
        }

        public void setGetPassword(String getPassword) {
            this.getPassword = getPassword;
        }
    }
}

