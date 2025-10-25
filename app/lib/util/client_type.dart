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
    return ClientType.browser; // Linux 桌面版暂时归类为 browser
  }
  return ClientType.browser;
}
