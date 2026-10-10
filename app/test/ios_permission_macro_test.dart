import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// iOS 权限宏契约。
///
/// 这条断言来自真实事故：`app/ios/Podfile` 只声明了相机 / 相册 / 麦克风三个宏，
/// 漏了 `PERMISSION_NOTIFICATIONS`，permission_handler_apple 便把「通知」当成未知权限编译：
/// `Permission.notification.status` 恒为 `denied`、`request()` 恒为 `permanentlyDenied`。
/// 结果是 iPhone 用户打开「学习提醒」设置页，永远看到「通知权限已关闭」，
/// 点「发送测试通知」也永远提示未获权限，且系统权限申请框根本不会弹。
/// 这一切在编译期和 Dart 侧都没有任何提示，只能在真机上肉眼发现。
void main() {
  test('ios/Podfile 必须为 permission_handler 声明 App 用到的权限宏', () {
    final podfile = File('ios/Podfile').readAsStringSync();

    for (final macro in const [
      'PERMISSION_CAMERA=1',
      'PERMISSION_PHOTOS=1',
      'PERMISSION_MICROPHONE=1',
      'PERMISSION_NOTIFICATIONS=1',
    ]) {
      expect(podfile.contains(macro), isTrue, reason: 'ios/Podfile 缺少 $macro');
    }
  });
}
