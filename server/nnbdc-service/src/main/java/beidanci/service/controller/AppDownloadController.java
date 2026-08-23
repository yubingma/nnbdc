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
 * 设备品牌优先识别：华为直达华为应用市场，小米直达小米应用商店，苹果直达AppStore
 */
@Controller
public class AppDownloadController {

    private static final Logger log = LoggerFactory.getLogger(AppDownloadController.class);

    /** Android 应用包名 */
    public static final String ANDROID_PACKAGE_NAME = "com.nn.nnbdc.android";

    /** 苹果 App Store 地址 */
    public static final String APP_STORE_URL = "https://apps.apple.com/app/id6756229006";

    /** 华为应用市场协议（直接基于真实包名直达应用详情页） */
    public static final String HUAWEI_MARKET_URL = "appmarket://details?id=" + ANDROID_PACKAGE_NAME;

    /** 小米应用商店协议 */
    public static final String XIAOMI_MARKET_URL = "mimarket://details?id=" + ANDROID_PACKAGE_NAME;

    /** 腾讯应用宝微下载地址（通用安卓微信兜底通道） */
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

        // 2. 优先识别各大手机厂商专属品牌（即使用户在微信内扫码，也优先直达手机自带官方市场）
        if (uaLower.contains("huawei") || uaLower.contains("honor") || uaLower.contains("hws") || uaLower.contains("harmonyos")) {
            // 华为 / 鸿蒙 / 荣耀手机 -> 华为应用市场
            log.info("App下载分流: 华为/鸿蒙设备 -> 华为应用市场, ua={}", userAgent);
            response.sendRedirect(HUAWEI_MARKET_URL);
            return;
        }

        if (uaLower.contains("xiaomi") || uaLower.contains("redmi") || uaLower.contains("mix ") || uaLower.contains("poco")) {
            // 小米 / 红米手机 -> 小米应用商店
            log.info("App下载分流: 小米设备 -> 小米应用商店, ua={}", userAgent);
            response.sendRedirect(XIAOMI_MARKET_URL);
            return;
        }

        // 3. 通用 Android 设备在微信内置浏览器打开时的兜底
        if (uaLower.contains("micromessenger")) {
            log.info("App下载分流: 通用Android(微信环境) -> 应用宝微下载, ua={}", userAgent);
            response.sendRedirect(TENCENT_MYAPP_URL);
            return;
        }

        // 4. 其他 Android 设备 (OPPO, vivo, 三星等) 在外部浏览器打开 -> 唤起系统内置应用市场
        log.info("App下载分流: 通用Android设备 -> 系统市场, ua={}", userAgent);
        response.sendRedirect(ANDROID_MARKET_URL);
    }
}
