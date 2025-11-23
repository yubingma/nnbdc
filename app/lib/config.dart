
class Config {
  static String profileName = "dev";

  static final Map profiles = {
    "prod": {
      "service_url": "http://back.nnbdc.com",
      "socketServerUrl": "http://back.nnbdc.com:9090/all",
      "sound_base_url": "http://www.nnbdc.com/sound/",
      "updateUrl": "http://www.nnbdc.com/app/ver.json",
      "apkUrl": "http://www.nnbdc.com/app/nnbdc-android.apk",
      "windowsUrl": "http://www.nnbdc.com/app/nnbdc-windows.zip",
      "linuxUrl": "http://www.nnbdc.com/app/nnbdc-linux.AppImage",
      "wordImageBaseUrl": 'http://www.nnbdc.com/img/word/'
    },
    "dev": {
      "service_url": "http://192.168.1.170:5200",
      "socketServerUrl": "http://192.168.1.170:9090/all",
      "sound_base_url": "http://192.168.1.170:80/sound/",
      "updateUrl": "http://192.168.1.170:80/app/ver.json",
      "apkUrl": "http://192.168.1.170:80/app/nnbdc-android.apk",
      "windowsUrl": "http://192.168.1.170:80/app/nnbdc-windows.zip",
      "linuxUrl": "http://192.168.1.170:80/app/nnbdc-linux.AppImage",
      "wordImageBaseUrl": 'http://192.168.1.170:80/img/word/'
    },
    "dev_web": {
      "service_url": "http://localhost:5200",
      "socketServerUrl": "http://localhost:9090/all",
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
  static final String soundBaseUrl = profile["sound_base_url"];
  static final String updateUrl = profile["updateUrl"];
  static final String apkUrl = profile["apkUrl"];
  static final String windowsUrl = profile["windowsUrl"];
  static final String linuxUrl = profile["linuxUrl"];
  static final String wordImageBaseUrl = profile["wordImageBaseUrl"];

  // Configuration for ThrottledDbSyncService
  static const Duration dbSyncThrottleInterval = Duration(seconds: 60);

  // Debug settings
  static bool get showDbButton {
    return profileName == "dev" || profileName == "dev_web" || profileName == "test";
  }
}
