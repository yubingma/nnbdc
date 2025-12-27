class Config {
  static String profileName = "prod";

  static final Map profiles = {
    "prod": {
      // 后端域名支持 HTTPS，iOS/macOS 也建议强制走 HTTPS，避免 ATS/审核问题
      "service_url": "https://back.nnbdc.com",
      // Socket.IO 走同域 HTTPS，由 nginx 转发到 9090（namespace: /all）
      "socketServerUrl": "https://back.nnbdc.com/all",
      // 公共资源/共享词书通过 CDN（www + /back 反代）访问
      "cdnBackUrl": "https://www.nnbdc.com/back",
      "sound_base_url": "https://www.nnbdc.com/sound/",
      "updateUrl": "https://www.nnbdc.com/app/ver.json",
      "apkUrl": "https://www.nnbdc.com/app/nnbdc-android.apk",
      "windowsUrl": "https://www.nnbdc.com/app/nnbdc-windows.zip",
      "linuxUrl": "https://www.nnbdc.com/app/nnbdc-linux.AppImage",
      "wordImageBaseUrl": 'https://www.nnbdc.com/img/word/'
    },
    "dev": {
      "service_url": "http://192.168.43.92:5200",
      "socketServerUrl": "http://192.168.43.92:9090/all",
      "cdnBackUrl": "http://192.168.43.92:5200",
      "sound_base_url": "http://192.168.43.92:80/sound/",
      "updateUrl": "http://192.168.43.92:80/app/ver.json",
      "apkUrl": "http://192.168.43.92:80/app/nnbdc-android.apk",
      "windowsUrl": "http://192.168.43.92:80/app/nnbdc-windows.zip",
      "linuxUrl": "http://192.168.43.92:80/app/nnbdc-linux.AppImage",
      "wordImageBaseUrl": 'http://192.168.43.92:80/img/word/'
    },
    "dev_web": {
      "service_url": "http://localhost:5200",
      "socketServerUrl": "http://localhost:9090/all",
      "cdnBackUrl": "http://localhost:80/back",
      "sound_base_url": "http://localhost:80/sound/",
      "updateUrl": "http://localhost:80/app/ver.json",
      "apkUrl": "http://localhost:80/app/nnbdc-android.apk",
      "windowsUrl": "http://localhost:80/app/nnbdc-windows.zip",
      "linuxUrl": "http://localhost:80/app/nnbdc-linux.AppImage",
      "wordImageBaseUrl": 'http://localhost:80/img/word/'
    },
    "test": {
      "service_url": "http://localhost:5201",
      "socketServerUrl": "http://localhost:9091/all",
      "cdnBackUrl": "http://localhost:80/back",
      "sound_base_url": "http://localhost:80/sound/",
      "updateUrl": "http://localhost:80/app/ver.json",
      "apkUrl": "http://localhost:80/app/nnbdc-android.apk",
      "windowsUrl": "http://localhost:80/app/nnbdc-windows.zip",
      "linuxUrl": "http://localhost:80/app/nnbdc-linux.AppImage",
      "wordImageBaseUrl": 'http://localhost:80/img/word/'
    }
  };

  static final Map profile = profiles[profileName];

  static final String serviceUrl = profile["service_url"];
  static final String socketServerUrl = profile["socketServerUrl"];
  static final String cdnBackUrl = profile["cdnBackUrl"];
  static final String soundBaseUrl = profile["sound_base_url"];
  static final String updateUrl = profile["updateUrl"];
  static final String apkUrl = profile["apkUrl"];
  static final String windowsUrl = profile["windowsUrl"];
  static final String linuxUrl = profile["linuxUrl"];
  static final String wordImageBaseUrl = profile["wordImageBaseUrl"];

  // Configuration for ThrottledDbSyncService
  static const Duration dbSyncThrottleInterval = Duration(seconds: 60);
}
