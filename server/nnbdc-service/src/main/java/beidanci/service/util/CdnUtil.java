package beidanci.service.util;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.aliyuncs.DefaultAcsClient;
import com.aliyuncs.IAcsClient;
import com.aliyuncs.cdn.model.v20180510.RefreshObjectCachesRequest;
import com.aliyuncs.cdn.model.v20180510.RefreshObjectCachesResponse;
import com.aliyuncs.exceptions.ClientException;
import com.aliyuncs.profile.DefaultProfile;

import beidanci.service.config.AliyunCdnProperties;

import java.net.URI;
import java.net.URISyntaxException;

/**
 * 阿里云CDN服务工具类
 */
@Component
public class CdnUtil {

    private static final Logger logger = LoggerFactory.getLogger(CdnUtil.class);

    @Autowired
    private AliyunCdnProperties properties;

    private IAcsClient client;

    private void initClient() {
        try {
            String accessKeyId = properties.getAccessKeyId();
            String accessKeySecret = properties.getAccessKeySecret();
            String regionId = properties.getRegionId();
            if (isBlank(accessKeyId) || isBlank(accessKeySecret)) {
                logger.error("阿里云CDN凭据未配置：请在 application.yml 中配置 aliyun.cdn.access-key-id/secret");
                client = null;
                return;
            }
            if (isBlank(regionId)) {
                regionId = "cn-hangzhou";
            }
            DefaultProfile profile = DefaultProfile.getProfile(regionId, accessKeyId, accessKeySecret);
            client = new DefaultAcsClient(profile);
        } catch (Exception e) {
            logger.error("初始化阿里云CDN客户端失败", e);
            client = null;
        }
    }

    private boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }

    /**
     * 刷新CDN缓存（支持文件和目录）
     * @param urls 需要刷新的URL列表，多个URL以换行符分隔
     * @param objectType 刷新类型：File（文件）或 Directory（目录）
     * @return 刷新结果
     */
    public String refreshCache(String urls, String objectType) {
        try {
            if (client == null) {
                initClient();
            }
            if (client == null) {
                return "CDN client not initialized";
            }

            // 验证URL是否为空
            if (isBlank(urls)) {
                logger.error("URL为空");
                return "URL为空，请检查URL格式";
            }
            
            // 将完整URL转换为路径格式（阿里云CDN会根据配置的域名自动添加前缀）
            String paths = convertUrlsToPaths(urls);
            logger.info("准备刷新CDN缓存，类型：{}，原始URL：\n{}，转换后路径：\n{}", objectType, urls, paths);
            
            if (isBlank(paths)) {
                logger.error("URL转换后路径为空");
                return "URL转换后路径为空，请检查URL格式";
            }
            
            RefreshObjectCachesRequest request = new RefreshObjectCachesRequest();
            request.setObjectPath(paths);
            request.setObjectType(objectType);

            RefreshObjectCachesResponse response = client.getAcsResponse(request);

            logger.info("CDN缓存刷新任务提交成功，刷新类型：{}，刷新任务ID：{}", objectType, response.getRefreshTaskId());
            return "OK";
        } catch (ClientException e) {
            logger.error("CDN缓存刷新失败，刷新类型：{}", objectType, e);
            return e.getMessage();
        }
    }

    /**
     * 将完整URL转换为路径格式
     * 例如: http://www.nnbdc.com/img/word/test.jpg -> /img/word/test.jpg
     * 阿里云CDN会根据配置的域名自动添加域名前缀，所以只需要路径部分
     */
    private String convertUrlsToPaths(String urls) {
        if (isBlank(urls)) {
            return "";
        }
        
        String[] urlLines = urls.split("\n");
        StringBuilder pathsBuilder = new StringBuilder();
        
        for (String urlLine : urlLines) {
            String trimmedUrl = urlLine.trim();
            if (trimmedUrl.isEmpty()) {
                continue;
            }
            
            try {
                URI uri = new URI(trimmedUrl);
                String path = uri.getPath();
                
                if (path == null || path.isEmpty()) {
                    // 如果没有路径，使用根路径
                    path = "/";
                }
                
                // 如果有查询参数，也需要包含
                if (uri.getQuery() != null && !uri.getQuery().isEmpty()) {
                    path += "?" + uri.getQuery();
                }
                
                if (pathsBuilder.length() > 0) {
                    pathsBuilder.append("\n");
                }
                pathsBuilder.append(path);
            } catch (URISyntaxException e) {
                logger.warn("URL解析失败，跳过: {}", trimmedUrl, e);
            }
        }
        
        return pathsBuilder.toString();
    }

    /**
     * 刷新单个URL的缓存
     * @param url 需要刷新的URL
     * @return 刷新结果
     */
    public String refreshUrl(String url) {
        return refreshCache(url, "File");
    }

    /**
     * 刷新目录缓存
     * @param url 需要刷新的目录URL
     * @return 刷新结果
     */
    public String refreshDirectory(String url) {
        return refreshCache(url, "Directory");
    }
}

