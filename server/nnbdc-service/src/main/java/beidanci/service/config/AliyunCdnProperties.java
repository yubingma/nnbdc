package beidanci.service.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 阿里云CDN配置属性
 */
@Component
@ConfigurationProperties(prefix = "aliyun.cdn")
public class AliyunCdnProperties {

    private String accessKeyId;
    private String accessKeySecret;
    private String regionId;

    /**
     * 静态资源对外的 CDN 地址前缀（客户端取图用的地址，如 https://www.nnbdc.com/img/）。
     * 源站删除文件后必须按这个前缀拼出的 URL 刷新 CDN 缓存，否则 CDN 上仍能取到已删的图。
     */
    private String imageBaseUrl;

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

    public String getImageBaseUrl() {
        return imageBaseUrl;
    }

    public void setImageBaseUrl(String imageBaseUrl) {
        this.imageBaseUrl = imageBaseUrl;
    }
}

