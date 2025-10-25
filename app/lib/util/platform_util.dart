import 'dart:io';
import 'package:flutter/foundation.dart';

class PlatformUtils {
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

  /// 判断当前平台是否支持ASR（语音识别）
  /// 目前只有iOS和Android平台支持ASR
  /// Web、Windows、macOS不支持
  static bool isAsrSupported() {
    return isIOS || isAndroid;
  }

  /// 判断当前平台是否支持英文ASR
  /// 目前只有iOS平台完全支持英文语音识别
  /// Android平台的英文ASR识别效果不佳，暂不支持
  static bool isEnglishAsrSupported() {
    return isIOS;
  }

  /// 判断当前平台是否支持TTS（文本转语音）
  /// 目前Android、iOS支持TTS
  static bool isTtsSupported() {
    return isAndroid || isIOS ;
  }
}
