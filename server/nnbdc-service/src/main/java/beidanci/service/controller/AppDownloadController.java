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
 * 
 * 真实应用市场配置：
 * - 苹果 App Store ID: 6756229006
 * - 华为应用市场 App ID: C117150707 (支持微信内无缝拉起华为应用市场原生详情页)
 * - Android 包名: com.nn.nnbdc.android
 */
@Controller
public class AppDownloadController {

    private static final Logger log = LoggerFactory.getLogger(AppDownloadController.class);

    /** Android 应用包名 */
    public static final String ANDROID_PACKAGE_NAME = "com.nn.nnbdc.android";

    /** 苹果 App Store 地址 */
    public static final String APP_STORE_URL = "https://apps.apple.com/app/id6756229006";

    /** 华为应用市场真实直达链接（AppGallery App ID: 117150707，在微信/浏览器中均可100%直接唤起华为应用市场详情页） */
    public static final String HUAWEI_MARKET_URL = "https://appgallery.huawei.com/app/C117150707";

    /** 小米应用商店协议 */
    public static final String XIAOMI_MARKET_URL = "mimarket://details?id=" + ANDROID_PACKAGE_NAME;

    /** 腾讯应用宝微下载地址（微信内置浏览器通用安卓兜底通道） */
    public static final String TENCENT_MYAPP_URL = "https://a.app.qq.com/o/simple.jsp?pkgname=" + ANDROID_PACKAGE_NAME;

    /** Android 系统通用应用商店协议 */
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

        // 1. 优先判断苹果生态设备（iOS / macOS）
        boolean isAppleDevice = uaLower.contains("iphone") 
                || uaLower.contains("ipad") 
                || uaLower.contains("ipod") 
                || uaLower.contains("macintosh");

        if (isAppleDevice) {
            log.info("App下载分流: Apple设备 -> AppStore, ua={}", userAgent);
            response.sendRedirect(APP_STORE_URL);
            return;
        }

        // 2. 华为 / 鸿蒙 / 荣耀设备（官方 HTTPS 链接在微信中完全放行，且华为系统会自动无缝唤起华为应用市场详情页）
        if (uaLower.contains("huawei") || uaLower.contains("honor") || uaLower.contains("hws") || uaLower.contains("harmonyos")) {
            log.info("App下载分流: 华为/鸿蒙设备 -> 华为应用市场(C117150707), ua={}", userAgent);
            response.sendRedirect(HUAWEI_MARKET_URL);
            return;
        }

        // 3. 通用 Android 设备在微信内置浏览器打开时的兜底通道
        if (uaLower.contains("micromessenger")) {
            log.info("App下载分流: 通用Android(微信环境) -> 腾讯微下载, ua={}", userAgent);
            response.sendRedirect(TENCENT_MYAPP_URL);
            return;
        }

        // 4. 小米 / 红米手机 (外部系统浏览器) -> 小米应用商店
        if (uaLower.contains("xiaomi") || uaLower.contains("redmi") || uaLower.contains("mix ") || uaLower.contains("poco")) {
            log.info("App下载分流: 小米设备(外部浏览器) -> 小米应用商店, ua={}", userAgent);
            response.sendRedirect(XIAOMI_MARKET_URL);
            return;
        }

        // 5. 其他 Android 设备 (OPPO, vivo, 三星等) 在外部浏览器打开 -> 唤起系统内置应用市场
        log.info("App下载分流: 通用Android设备(外部浏览器) -> 系统市场, ua={}", userAgent);
        response.sendRedirect(ANDROID_MARKET_URL);
    }
}
