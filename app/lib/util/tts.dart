import 'dart:async';
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
  
  // 引入异步锁，确保串行执行
  Future? _activeSpeakFuture;
  bool _isSpeaking = false;
  bool _stopRequested = false;

  bool get isSpeaking => _isSpeaking;

  onTtsEvent(event) {
    Global.logger.d('TTS 收到事件: $event');
    if (event['type'] == 'initStatus') {
      initialized = event['data'] == 0;
      Global.logger.d('TTS 初始化状态: $initialized');
    } else if (event['type'] == 'ttsCompleted') {
      final utteranceId = event['data'];
      Global.logger.d('TTS 完成事件: $utteranceId');
      completedUtterances.add(utteranceId);
      _isSpeaking = false;
    } else if (event['type'] == 'ttsStarted') {
      _isSpeaking = true;
    }
  }

  Future<bool> isReady() async {
    if (!PlatformUtils.isTtsSupported()) return false;
    if (initialized) return true;

    // 如果还没监听，先初始化监听
    await init();

    // 等待初始化状态返回，最多等待 2 秒
    for (int i = 0; i < 100; i++) {
      if (initialized) return true;
      await Future.delayed(const Duration(milliseconds: 20));
    }
    return initialized;
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
    if (!PlatformUtils.isTtsSupported() || text.trim().isEmpty) {
      return;
    }

    _stopRequested = false; // 每次新的 speak 开始前，重置停止请求标记

    // 等待上一个播放任务结束 (简单的 Mutex 实现)
    while (_activeSpeakFuture != null) {
      await _activeSpeakFuture;
    }

    Completer completer = Completer();
    _activeSpeakFuture = completer.future;

    try {
      await _doSpeak(text);
    } finally {
      _activeSpeakFuture = null;
      completer.complete();
    }
  }

  Future<void> _doSpeak(String text) async {
    // 自动判断语言
    String language = _detectLanguage(text);
    Global.logger.d('TTS _doSpeak: $text, language: $language');
    
    try {
      // 文本转语音播放
      var uuid = const Uuid();
      final utteranceId = uuid.v4();
      
      // 调整估算语速，更接近真实水平 (中文 4.5 字/秒, 英文 3.5 词/秒)
      double charsPerSecond = language == 'zh-CN' ? 4.5 : 3.5;
      int estimatedDurationMs = (text.length / charsPerSecond * 1000).round();
      // 兜底保护时间：如果没收到事件，最多等估算时间的 1.5 倍
      int fallbackDurationMs = (estimatedDurationMs * 1.5).round().clamp(1000, 15000);
      
      final startTime = DateTime.now();
      await methodChannel.invokeMethod('speak', {'text': text, 'utteranceId': utteranceId, 'language': language});
      _isSpeaking = true;

      // 等待播放完成，结合事件回调和时间保护
      int attempts = 0;
      final maxAttempts = 1000; // 1000 × 20ms = 20s
      Global.logger.d('TTS 开始等待完成: $utteranceId, 估算时长: ${estimatedDurationMs}ms, 兜底时长: ${fallbackDurationMs}ms');

      while (attempts < maxAttempts) {
        if (_stopRequested) {
          Global.logger.d('TTS 收到停止请求，中断等待循环: $utteranceId');
          break;
        }

        await Future.delayed(const Duration(milliseconds: 20));
        attempts++;
        
        final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
        
        // 1. 优先信任完成事件：一旦收到事件，稍微缓冲一下即退出
        if (completedUtterances.contains(utteranceId)) {
          // 额外等待一个极短的时间，确保硬件缓冲区播放完毕
          await Future.delayed(const Duration(milliseconds: 100));
          Global.logger.d('TTS 播放完成事件触发: $utteranceId, 实际耗时: ${elapsedMs + 100}ms');
          break;
        }

        // 2. 兜底逻辑：如果一直没收到事件，但已经超过了合理的兜底时长
        if (elapsedMs >= fallbackDurationMs) {
          Global.logger.w('TTS 等待超时(触发兜底): $utteranceId, 强制结束');
          break;
        }

        // 每 100 次（2秒）打印一次日志
        if (attempts % 100 == 0) {
          Global.logger.d('TTS 等待中: $utteranceId, 已等待 ${elapsedMs}ms');
        }
      }

      completedUtterances.remove(utteranceId);
    } on PlatformException catch (e) {
      ErrorHandler.handleError(e, null, logPrefix: 'TTS异常', showToast: false);
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: 'TTS异常', showToast: false);
    } finally {
      _isSpeaking = false;
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

  Future<void> stop() async {
    // 在 Android 和 iOS 平台上使用 TTS，Web 不支持
    if (!PlatformUtils.isAndroid && !PlatformUtils.isIOS) {
      return;
    }

    _stopRequested = true; // 设置停止标记，中断正在执行的 _doSpeak 循环

    try {
      await methodChannel.invokeMethod('stop');
      _isSpeaking = false;
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace,
          logPrefix: 'TTS停止异常', showToast: false);
    }
  }

  Future<bool> checkLanguageSupport(String language) async {
    if (!PlatformUtils.isTtsSupported()) {
      return false;
    }

    try {
      // 确保已经初始化
      bool ready = await isReady();
      if (!ready) {
        Global.logger.e('TTS 无法初始化，可能不支持本地TTS');
        return false;
      }

      final dynamic result = await methodChannel
          .invokeMethod('checkLanguageSupport', {'language': language});
      return result == true;
    } catch (e) {
      Global.logger.e("检查TTS语言支持失败 ($language): $e");
      return false;
    }
  }
}
