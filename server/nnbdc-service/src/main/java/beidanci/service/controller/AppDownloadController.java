package beidanci.service.controller;

import java.io.IOException;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

/**
 * 移动应用下载智能分流控制器
 * 访问 /app 时根据用户设备 User-Agent 智能分流至对应官方应用市场
 * 100% 节省自建 CDN/服务器流量成本，提升各大应用商店自然搜索权重与下载量
 */
@Controller
public class AppDownloadController {

    private static final Logger log = LoggerFactory.getLogger(AppDownloadController.class);

    /** Android 应用包名 */
    public static final String ANDROID_PACKAGE_NAME = "com.nn.nnbdc.android";

    /** 苹果 App Store 地址 */
    public static final String APP_STORE_URL = "https://apps.apple.com/app/id6756229006";

    /** 华为应用市场协议 */
    public static final String HUAWEI_MARKET_URL = "appmarket://details?id=" + ANDROID_PACKAGE_NAME;

    /** 小米应用商店协议 */
    public static final String XIAOMI_MARKET_URL = "mimarket://details?id=" + ANDROID_PACKAGE_NAME;

    /** 腾讯应用宝微下载地址（微信内置及通用安卓下载首选通道，微信内支持无缝唤起各厂商市场） */
    public static final String TENCENT_MYAPP_URL = "https://a.app.qq.com/o/simple.jsp?pkgname=" + ANDROID_PACKAGE_NAME;

    /** Android 系统通用应用商店协议（直接唤起手机自带的内置应用市场） */
    public static final String ANDROID_MARKET_URL = "market://details?id=" + ANDROID_PACKAGE_NAME;

    /**
     * 扫码智能分流跳转
     */
    @GetMapping("/app")
    public void downloadRedirect(HttpServletRequest request, HttpServletResponse response) throws IOException {
        String userAgent = request.getHeader("User-Agent");
        if (userAgent == null) {
            userAgent = "";
        }
        String uaLower = userAgent.toLowerCase();

        // 1. 判断是否为 iOS / macOS 苹果生态设备
        boolean isAppleDevice = uaLower.contains("iphone") 
                || uaLower.contains("ipad") 
                || uaLower.contains("ipod") 
                || uaLower.contains("macintosh");

        if (isAppleDevice) {
            log.info("App下载分流: Apple设备 -> AppStore, ua={}", userAgent);
            response.sendRedirect(APP_STORE_URL);
            return;
        }

        // 2. 判断是否在微信内置浏览器中打开（Android端）
        boolean isWeChat = uaLower.contains("micromessenger");
        if (isWeChat) {
            // 微信对直接 apk/market intent 有拦截，通过应用宝微下载可智能拉起手机厂商市场或官方通道
            log.info("App下载分流: 微信内置浏览器(Android) -> 应用宝微下载, ua={}", userAgent);
            response.sendRedirect(TENCENT_MYAPP_URL);
            return;
        }

        // 3. 判断主流 Android 厂商专属应用市场
        String targetUrl;
        if (uaLower.contains("huawei") || uaLower.contains("honor") || uaLower.contains("hws") || uaLower.contains("harmonyos")) {
            // 华为 / 鸿蒙 / 荣耀手机 -> 华为应用市场
            targetUrl = HUAWEI_MARKET_URL;
        } else if (uaLower.contains("xiaomi") || uaLower.contains("redmi") || uaLower.contains("mix ") || uaLower.contains("poco")) {
            // 小米 / 红米手机 -> 小米应用商店
            targetUrl = XIAOMI_MARKET_URL;
        } else {
            // 其他 Android 手机 (OPPO, vivo, 魅族, 三星等) -> 唤起系统内置应用商店
            targetUrl = ANDROID_MARKET_URL;
        }

        log.info("App下载分流: Android设备 -> {}, ua={}", targetUrl, userAgent);
        response.sendRedirect(targetUrl);
    }
}
