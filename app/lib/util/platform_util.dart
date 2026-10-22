import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PlatformUtils {
  /// 测试专用：覆盖 ASR 支持判定（null = 按平台自动判断）。
  /// 单元测试环境运行在 macOS 上，Platform.isIOS/isAndroid 均为 false，
  /// 无法验证 PTT 按下→启动识别的链路，故允许测试注入 true。
  @visibleForTesting
  static bool? asrSupportedOverride;
  @visibleForTesting
  static bool? englishAsrSupportedOverride;
  @visibleForTesting
  static bool? isDesktopOverride;

  static bool get isDesktop =>
      isDesktopOverride ?? (!isTesting && (isWindows || isLinux || isMacOS));

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
    return englishAsrSupportedOverride ?? asrSupportedOverride ?? (isIOS || isAndroid);
  }

  @visibleForTesting
  static bool? ttsSupportedOverride;

  /// 判断当前平台是否支持TTS（文本转语音）
  /// 目前Android、iOS支持TTS
  static bool isTtsSupported() {
    return ttsSupportedOverride ?? (isAndroid || isIOS);
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
        // 关键：先移除 'android' 和 'droid' 单词，避免系统原生进程名中的 'droi' 子串误命中
        final sanitized = content.replaceAll('android', '').replaceAll('droid', '');
        // 卓易通容器特征：华为 isulad 容器引擎，或包含 zhuoyi、卓易通、droi 特征路径/包名
        if (sanitized.contains('isulad') ||
            sanitized.contains('zhuoyi') ||
            sanitized.contains('卓易通') ||
            sanitized.contains('droi/') ||
            sanitized.contains('droi_') ||
            sanitized.contains('com.droi')) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Android 设备厂商，启动时由 [initAndroidDeviceInfo] 读取并归并。
  static String? _androidVendor;

  /// 启动时预取 Android 设备厂商，供后端日志把 Android 细分为
  /// 华为/荣耀/小米/OPPO/vivo 等。只读 Build.BRAND 与 Build.MANUFACTURER，无需权限。
  static Future<void> initAndroidDeviceInfo() async {
    if (!isAndroid) return;
    try {
      const channel = MethodChannel('nnbdc/device_info');
      final info = await channel.invokeMapMethod<String, String>('getAndroidVendor');
      _androidVendor = normalizeAndroidVendor(info?['brand'], info?['manufacturer']);
    } catch (e) {
      debugPrint('读取 Android 设备厂商失败，后端日志将只显示 Android: $e');
    }
  }

  /// 把 Build.BRAND / Build.MANUFACTURER 归并成日志里的厂商名。
  /// 子品牌跟随母品牌：Redmi/POCO 归小米，iQOO 归 vivo，一加/realme 归 OPPO。
  @visibleForTesting
  static String? normalizeAndroidVendor(String? brand, String? manufacturer) {
    final candidates = [brand, manufacturer]
        .map((value) => value?.trim().toUpperCase() ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
    for (final key in candidates) {
      final known = _androidVendorAliases[key];
      if (known != null) return known;
    }
    return candidates.isEmpty ? null : _titleCase(candidates.first);
  }

  static String _titleCase(String value) => value[0] + value.substring(1).toLowerCase();

  static const Map<String, String> _androidVendorAliases = {
    'HUAWEI': 'Huawei',
    'HONOR': 'Honor',
    'XIAOMI': 'Xiaomi',
    'REDMI': 'Xiaomi',
    'POCO': 'Xiaomi',
    'OPPO': 'OPPO',
    'ONEPLUS': 'OPPO',
    'REALME': 'OPPO',
    'VIVO': 'vivo',
    'IQOO': 'vivo',
  };

  static String get platformLabel {
    if (isWeb) return 'Web';
    if (isAndroid) {
      final vendor = _androidVendor;
      final zhuoyiTong = isZhuoyiTong ? ' (卓易通)' : '';
      return vendor == null ? 'Android$zhuoyiTong' : 'Android/$vendor$zhuoyiTong';
    }
    if (isIOS) return 'iOS';
    if (isMacOS) return 'macOS';
    if (isWindows) return 'Windows';
    if (isLinux) return 'Linux';
    return 'Unknown';
  }

  /// 是否运行在 Flutter 单元测试环境中
  static bool get isUnitTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// 是否为小米系设备（小米 / Redmi / POCO）。
  ///
  /// 厂商信息由 [initAndroidDeviceInfo] 在启动时读取并归并。
  static bool get isXiaomiDevice => _androidVendor == 'Xiaomi';

  /// 是否「明确不是小米」——即白名单内的其他厂商机型（华为/荣耀/OPPO/vivo 等）。
  ///
  /// 厂商信息没读到时返回 false（按"可能是小米"处理），确保小米审核用云真机
  /// 读不到品牌时也不会漏隐藏 K12 内容。
  static bool get isConfirmedNonXiaomiDevice =>
      _androidVendor != null && _androidVendor != 'Xiaomi';
}
