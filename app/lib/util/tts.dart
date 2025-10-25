import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:uuid/uuid.dart';

class Tts {
  var methodChannel = const MethodChannel('nnbdc/tts_commands');
  var eventChannel = const EventChannel('nnbdc/tts_events');
  bool initialized = false;
  HashSet completedUtterances = HashSet();

  onTtsEvent(event) {
    Global.logger.d('TTS 收到事件: $event');
    if (event['type'] == 'initStatus') {
      initialized = event['data'] == 0;
      Global.logger.d('TTS 初始化状态: $initialized');
    } else if (event['type'] == 'ttsCompleted') {
      final utteranceId = event['data'];
      Global.logger.d('TTS 完成事件: $utteranceId');
      completedUtterances.add(utteranceId);
    }
  }

  init() async {
    // 只在支持TTS的平台上初始化
    if (PlatformUtils.isTtsSupported()) {
      try {
        Global.logger.d('TTS 开始初始化 EventChannel 监听');
        eventChannel.receiveBroadcastStream("nnbdc/tts_events").listen(
          onTtsEvent,
          onError: (error) {
            Global.logger.e('TTS EventChannel 错误: $error');
          },
          onDone: () {
            Global.logger.d('TTS EventChannel 连接关闭');
          },
        );
        Global.logger.d('TTS EventChannel 监听设置成功');
      } catch (e) {
        // 忽略平台不支持的错误
        Global.logger.e("TTS初始化失败: $e");
      }
    }
  }

  Future<void> speak(String text) async {
    if (!PlatformUtils.isTtsSupported()) {
      return;
    }

    // 自动判断语言
    String language = _detectLanguage(text);
    Global.logger.d('TTS speak: $text, language: $language');
    try {
      // 文本转语音播放
      var uuid = const Uuid();
      final utteranceId = uuid.v4();
      await methodChannel.invokeMethod('speak', {'text': text, 'utteranceId': utteranceId, 'language': language});

      // 等待播放完成，最多等待 10 秒
      int attempts = 0;
      final maxAttempts = 500; // 500 × 20ms = 10s
      Global.logger.d('TTS 开始等待完成: $utteranceId');

      while (!completedUtterances.contains(utteranceId) && attempts < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 20), () {});
        attempts++;

        // 每 100 次（2秒）打印一次日志
        if (attempts % 100 == 0) {
          Global.logger.d('TTS 等待中: $utteranceId, 已等待 ${attempts * 20}ms');
        }
      }

      if (attempts >= maxAttempts) {
        Global.logger.d("TTS 播放超时，强制继续: $utteranceId");
      } else {
        Global.logger.d('TTS 播放完成: $utteranceId');
      }

      completedUtterances.remove(utteranceId);
    } on PlatformException catch (e) {
      ErrorHandler.handleError(e, null, logPrefix: 'TTS异常', showToast: false);
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: 'TTS异常', showToast: false);
    }
  }

  // 基于文本长度估算 TTS 播放时间的备选方案
  Future<void> speakWithTimeout(String text) async {
    if (!PlatformUtils.isTtsSupported()) {
      return;
    }

    // 自动判断语言
    String language = _detectLanguage(text);
    Global.logger.d('TTS speakWithTimeout: $text, language: $language');
    try {
      // 文本转语音播放
      var uuid = const Uuid();
      final utteranceId = uuid.v4();
      await methodChannel.invokeMethod('speak', {'text': text, 'utteranceId': utteranceId, 'language': language});

      // 基于文本长度估算播放时间（中文约 3 字/秒，英文约 5 字/秒）
      double charsPerSecond = language == 'zh-CN' ? 3.0 : 5.0;
      int estimatedDuration = (text.length / charsPerSecond * 1000).round();

      // 等待估算的播放时间，最少 1 秒，最多 5 秒
      int waitTime = estimatedDuration.clamp(1000, 5000);
      Global.logger.d('TTS 估算播放时间: ${waitTime}ms (文本长度: ${text.length})');

      await Future.delayed(Duration(milliseconds: waitTime));
      Global.logger.d('TTS 播放完成（基于时间估算）: $utteranceId');
    } on PlatformException catch (e) {
      ErrorHandler.handleError(e, null, logPrefix: 'TTS异常', showToast: false);
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: 'TTS异常', showToast: false);
    }
  }

  // 自动检测语言（简单判断是否包含中文字符）
  String _detectLanguage(String text) {
    final chineseReg = RegExp(r'[\u4e00-\u9fa5]');
    if (chineseReg.hasMatch(text)) {
      return 'zh-CN';
    } else {
      return 'en-US';
    }
  }

  stop() {
    // 在 Android 和 iOS 平台上使用 TTS，Web 不支持
    if (!PlatformUtils.isAndroid && !PlatformUtils.isIOS) {
      return;
    }

    try {
      methodChannel.invokeMethod('stop');
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: 'TTS停止异常', showToast: false);
    }
  }
}
