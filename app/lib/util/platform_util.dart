import 'dart:io';
import 'package:flutter/foundation.dart';

class PlatformUtils {
  /// 测试专用：覆盖 ASR 支持判定（null = 按平台自动判断）。
  /// 单元测试环境运行在 macOS 上，Platform.isIOS/isAndroid 均为 false，
  /// 无法验证 PTT 按下→启动识别的链路，故允许测试注入 true。
  @visibleForTesting
  static bool? asrSupportedOverride;

  static bool _isWeb() {
    // 通过kIsWeb变量判断是否为web环境!
    return kIsWeb == true;
  }

  static bool _isAndroid() {
    return _isWeb() ? false : Platform.isAndroid;
  }

  static bool _isIOS() {
    return _isWeb() ? false : Platform.isIOS;
  }

  static bool _isMacOS() {
    return _isWeb() ? false : Platform.isMacOS;
  }

  static bool _isWindows() {
    return _isWeb() ? false : Platform.isWindows;
  }

  static bool _isFuchsia() {
    return _isWeb() ? false : Platform.isFuchsia;
  }

  static bool _isLinux() {
    return _isWeb() ? false : Platform.isLinux;
  }

  static bool get isWeb => _isWeb();

  static bool get isAndroid => _isAndroid();

  static bool get isIOS => _isIOS();

  static bool get isMacOS => _isMacOS();

  static bool get isWindows => _isWindows();

  static bool get isFuchsia => _isFuchsia();

  static bool get isLinux => _isLinux();

  static bool get isTesting => kDebugMode && Platform.environment.containsKey('FLUTTER_TEST');

  /// 判断当前平台是否支持ASR（语音识别）
  /// 目前只有iOS和Android平台支持ASR
  /// Web、Windows、macOS不支持
  static bool isAsrSupported() {
    return asrSupportedOverride ?? (isIOS || isAndroid);
  }

  /// 判断当前平台是否支持英文ASR
  /// iOS 和 Android (Sherpa-ONNX) 都支持英文语音识别
  static bool isEnglishAsrSupported() {
    return isIOS || isAndroid;
  }

  /// 判断当前平台是否支持TTS（文本转语音）
  /// 目前Android、iOS支持TTS
  static bool isTtsSupported() {
    return isAndroid || isIOS;
  }

  /// 测试专用：覆盖卓易通环境判定（null = 自动检测）
  @visibleForTesting
  static bool? zhuoyiTongOverride;

  /// 判断当前是否运行在鸿蒙卓易通等容器兼容环境中
  static bool get isZhuoyiTong {
    if (zhuoyiTongOverride != null) return zhuoyiTongOverride!;
    if (!isAndroid) return false;
    try {
      final cgroupFile = File('/proc/self/cgroup');
      if (cgroupFile.existsSync()) {
        final content = cgroupFile.readAsStringSync().toLowerCase();
        if (content.contains('isulad') ||
            content.contains('droi') ||
            content.contains('zhuoyi') ||
            content.contains('卓易通')) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  static String get platformLabel {
    if (isWeb) return 'Web';
    if (isAndroid) return isZhuoyiTong ? 'Android (卓易通)' : 'Android';
    if (isIOS) return 'iOS';
    if (isMacOS) return 'macOS';
    if (isWindows) return 'Windows';
    if (isLinux) return 'Linux';
    return 'Unknown';
  }
}
