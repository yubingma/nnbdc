import 'package:nnbdc/util/platform_util.dart';

import '../api/enum.dart';

ClientType getClientType() {
  if (PlatformUtils.isAndroid) {
    return ClientType.android;
  }
  if (PlatformUtils.isIOS) {
    return ClientType.ios;
  }
  if (PlatformUtils.isWindows) {
    return ClientType.windows;
  }
  if (PlatformUtils.isMacOS) {
    return ClientType.macos;
  }
  if (PlatformUtils.isLinux) {
    return ClientType.linux; // Linux 桌面版
  }
  return ClientType.browser;
}
