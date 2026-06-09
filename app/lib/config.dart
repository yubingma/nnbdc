class Config {
  static String profileName = "dev2";

  static final Map profiles = {
    "prod": {
      // 后端域名支持 HTTPS，iOS/macOS 也建议强制走 HTTPS，避免 ATS/审核问题
      "service_url": "https://back.nnbdc.com",
      // Socket.IO 走同域 HTTPS，由 nginx 转发到 9191（namespace: /all）
      "socketServerUrl": "https://back.nnbdc.com/all",
      // 公共资源/共享词书通过 CDN（www + /back 反代）访问 
      "cdnBackUrl": "https://www.nnbdc.com/back",
      "sound_base_url": "https://www.nnbdc.com/sound/",
      "updateUrl": "https://www.nnbdc.com/app/ver.json",
      "apkUrl": "https://www.nnbdc.com/app/nnbdc-android.apk",
      "windowsUrl": "https://www.nnbdc.com/app/nnbdc-windows.zip",
      "linuxUrl": "https://www.nnbdc.com/app/nnbdc-linux.AppImage",
      "aiModelUrl": "https://www.nnbdc.com/ai-model/meta.json",
      "imgBaseUrl": 'https://www.nnbdc.com/img/',
    },
    "dev": {
      "service_url": "http://192.168.1.230:5200",
      "socketServerUrl": "http://192.168.1.230:9191/all",
      "cdnBackUrl": "http://192.168.1.230:5200",
      "sound_base_url": "http://192.168.1.230:80/sound/",
      "updateUrl": "http://192.168.1.230:80/app/ver.json",
      "apkUrl": "http://192.168.1.230:80/app/nnbdc-android.apk",
      "windowsUrl": "http://192.168.1.230:80/app/nnbdc-windows.zip",
      "linuxUrl": "http://192.168.1.230:80/app/nnbdc-linux.AppImage",
      "aiModelUrl": "https://www.nnbdc.com/ai-model/meta.json",
      "imgBaseUrl": 'http://192.168.1.230:80/img/',
    },
    "dev2": {
      "service_url": "http://192.168.100.159:5200",
      "socketServerUrl": "http://192.168.100.159:9191/all",
      "cdnBackUrl": "http://192.168.100.159:5200",
      "sound_base_url": "http://192.168.100.159:80/sound/",
      "updateUrl": "http://192.168.100.159:80/app/ver.json",
      "apkUrl": "http://192.168.100.159:80/app/nnbdc-android.apk",
      "windowsUrl": "http://192.168.100.159:80/app/nnbdc-windows.zip",
      "linuxUrl": "http://192.168.100.159:80/app/nnbdc-linux.AppImage",
      "aiModelUrl": "https://www.nnbdc.com/ai-model/meta.json",
      "imgBaseUrl": 'http://192.168.100.159:80/img/',
    },
    "dev_web": {
      "service_url": "http://localhost:5200",
      "socketServerUrl": "http://localhost:9191/all",
      "cdnBackUrl": "http://localhost:80/back",
      "sound_base_url": "http://localhost:80/sound/",
      "updateUrl": "http://localhost:80/app/ver.json",
      "apkUrl": "http://localhost:80/app/nnbdc-android.apk",
      "windowsUrl": "http://localhost:80/app/nnbdc-windows.zip",
      "linuxUrl": "http://localhost:80/app/nnbdc-linux.AppImage",
      "aiModelUrl": "https://www.nnbdc.com/ai-model/meta.json",
      "imgBaseUrl": 'http://localhost:80/img/',
    }
  };

  static Map get profile => profiles[profileName];

  static String get serviceUrl => profile["service_url"];
  static String get socketServerUrl => profile["socketServerUrl"];
  static String get cdnBackUrl => profile["cdnBackUrl"];
  static String get soundBaseUrl => profile["sound_base_url"];
  static String get updateUrl => profile["updateUrl"];
  static String get apkUrl => profile["apkUrl"];
  static String get windowsUrl => profile["windowsUrl"];
  static String get linuxUrl => profile["linuxUrl"];
  static String get aiModelUrl => profile["aiModelUrl"];
  static String get imgBaseUrl => profile["imgBaseUrl"];
  
  // Umeng Configuration
  static const String umengAndroidAppKey = '69b011176f259537c773e1f0';
  static const String umengIosAppKey = '69b013cf6f259537c773e237';
  static const String umengChannel = 'AppStore';

  // Configuration for ThrottledDbSyncService
  static const Duration dbSyncThrottleInterval = Duration(seconds: 600);

  // Client secret for Nginx interception
  static const String clientSecret = 'ppdc-official-client-key-7788';
}
