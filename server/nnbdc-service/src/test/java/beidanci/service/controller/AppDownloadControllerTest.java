package beidanci.service.controller;

import java.io.IOException;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.junit.jupiter.api.Assertions.assertEquals;

public class AppDownloadControllerTest {

    private final AppDownloadController controller = new AppDownloadController();

    @Test
    public void testIPhoneRedirectsToAppStore() throws IOException {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15");
        MockHttpServletResponse response = new MockHttpServletResponse();

        controller.downloadRedirect(request, response);

        assertEquals(302, response.getStatus());
        assertEquals(AppDownloadController.APP_STORE_URL, response.getRedirectedUrl());
    }

    @Test
    public void testIPadRedirectsToAppStore() throws IOException {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("User-Agent", "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15");
        MockHttpServletResponse response = new MockHttpServletResponse();

        controller.downloadRedirect(request, response);

        assertEquals(302, response.getStatus());
        assertEquals(AppDownloadController.APP_STORE_URL, response.getRedirectedUrl());
    }

    @Test
    public void testHuaweiDeviceInWeChatRedirectsToHuaweiMarket() throws IOException {
        // 关键测试：华为手机即使在微信内置浏览器内扫码，也优先直达华为应用市场
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("User-Agent", "Mozilla/5.0 (Linux; Android 12; HUAWEI NOH-AN00) AppleWebKit/537.36 MicroMessenger/8.0.38");
        MockHttpServletResponse response = new MockHttpServletResponse();

        controller.downloadRedirect(request, response);

        assertEquals(302, response.getStatus());
        assertEquals(AppDownloadController.HUAWEI_MARKET_URL, response.getRedirectedUrl());
    }

    @Test
    public void testHuaweiDeviceInBrowserRedirectsToHuaweiMarket() throws IOException {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("User-Agent", "Mozilla/5.0 (Linux; Android 12; HUAWEI NOH-AN00) AppleWebKit/537.36 Chrome/99.0.4844.88 Mobile");
        MockHttpServletResponse response = new MockHttpServletResponse();

        controller.downloadRedirect(request, response);

        assertEquals(302, response.getStatus());
        assertEquals(AppDownloadController.HUAWEI_MARKET_URL, response.getRedirectedUrl());
    }

    @Test
    public void testXiaomiDeviceInWeChatRedirectsToXiaomiMarket() throws IOException {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("User-Agent", "Mozilla/5.0 (Linux; Android 14; 23127PN0CC; Xiaomi) AppleWebKit/537.36 MicroMessenger/8.0.38");
        MockHttpServletResponse response = new MockHttpServletResponse();

        controller.downloadRedirect(request, response);

        assertEquals(302, response.getStatus());
        assertEquals(AppDownloadController.XIAOMI_MARKET_URL, response.getRedirectedUrl());
    }

    @Test
    public void testGenericAndroidInWeChatRedirectsToTencentMyApp() throws IOException {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("User-Agent", "Mozilla/5.0 (Linux; Android 13; GenericPhone) AppleWebKit/537.36 MicroMessenger/8.0.38");
        MockHttpServletResponse response = new MockHttpServletResponse();

        controller.downloadRedirect(request, response);

        assertEquals(302, response.getStatus());
        assertEquals(AppDownloadController.TENCENT_MYAPP_URL, response.getRedirectedUrl());
    }

    @Test
    public void testGenericAndroidInBrowserRedirectsToSystemMarket() throws IOException {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("User-Agent", "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile");
        MockHttpServletResponse response = new MockHttpServletResponse();

        controller.downloadRedirect(request, response);

        assertEquals(302, response.getStatus());
        assertEquals(AppDownloadController.ANDROID_MARKET_URL, response.getRedirectedUrl());
    }
}
