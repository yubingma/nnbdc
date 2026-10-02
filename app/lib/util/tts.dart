import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:uuid/uuid.dart';

class Tts {
  var methodChannel = const MethodChannel('nnbdc/tts_commands');
  var eventChannel = const EventChannel('nnbdc/tts_events');
  bool initialized = false;
  final completedUtterances = <String>{};
  
  // 抢占代际标记与状态
  int _currentGeneration = 0;
  Future<void>? _activeSpeakFuture;
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

  /// 播放文本语音。
  /// 采用抢占式设计：新发音请求会立即打断并丢弃上一条发音，杜绝串行排队。
  Future<void> speak(String text) async {
    if (!PlatformUtils.isTtsSupported() || text.trim().isEmpty) {
      return;
    }

    final generation = ++_currentGeneration;

    // 抢占停止前一个发音
    if (_isSpeaking || _activeSpeakFuture != null) {
      _stopRequested = true;
      try {
        await methodChannel.invokeMethod('stop');
      } catch (_) {}
      if (_activeSpeakFuture != null) {
        try {
          await _activeSpeakFuture;
        } catch (_) {}
      }
    }

    // 若在停止/等待期间产生了更新的 speak，本请求被抢占，直接作废
    if (generation != _currentGeneration) {
      return;
    }

    _stopRequested = false;
    final completer = Completer<void>();
    _activeSpeakFuture = completer.future;

    try {
      await _doSpeak(text, generation);
    } finally {
      if (_activeSpeakFuture == completer.future) {
        _activeSpeakFuture = null;
      }
      completer.complete();
    }
  }

  Future<void> _doSpeak(String text, int generation) async {
    // 自动判断语言
    String language = _detectLanguage(text);
    Global.logger.d('TTS _doSpeak: $text, language: $language');
    
    try {
      // 文本转语音播放
      var uuid = const Uuid();
      final utteranceId = uuid.v4();
      
      // 合理估算语速与保护时长
      int estimatedDurationMs;
      if (language == 'zh-CN') {
        // 中文约 4.5 字/秒，加上前后各 100ms 缓冲
        estimatedDurationMs = (text.length / 4.5 * 1000).round() + 200;
      } else {
        // 英文按词数估算 (平均约 2.8 词/秒，每词约 350ms，加 200ms 首尾缓冲)
        final words = text.trim().split(RegExp(r'\s+')).length;
        estimatedDurationMs = (words * 350) + 200;
      }
      // 兜底保护时间：如果没收到原生完成事件，最多等估算时间的 1.5 倍
      int fallbackDurationMs = (estimatedDurationMs * 1.5).round().clamp(800, 15000);
      
      final startTime = DateTime.now();
      await methodChannel.invokeMethod('speak', {'text': text, 'utteranceId': utteranceId, 'language': language});
      _isSpeaking = true;
      debugPrint('🗣️ [AudioDiag] TTS开始: id=$utteranceId, text="$text", lang=$language, 估算=${estimatedDurationMs}ms');

      // 等待播放完成，结合事件回调和时间保护
      int attempts = 0;
      final maxAttempts = 1000; // 1000 × 20ms = 20s
      Global.logger.d('TTS 开始等待完成: $utteranceId, 估算时长: ${estimatedDurationMs}ms, 兜底时长: ${fallbackDurationMs}ms');

      while (attempts < maxAttempts) {
        // 关键：检测到停止请求或已被更新的发音抢占，立即终止等待循环
        if (_stopRequested || generation != _currentGeneration) {
          Global.logger.d('TTS 收到停止或抢占请求，中断等待循环: $utteranceId');
          break;
        }

        await Future.delayed(const Duration(milliseconds: 20));
        attempts++;
        
        final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
        
        // 1. 优先信任完成事件：一旦收到事件，稍微缓冲一下即退出
        if (completedUtterances.contains(utteranceId)) {
          // 额外等待一个极短的时间，确保硬件缓冲区播放完毕
          await Future.delayed(const Duration(milliseconds: 60));
          debugPrint('🗣️ [AudioDiag] TTS完成(事件): id=$utteranceId, 实际=${elapsedMs + 60}ms');
          Global.logger.d('TTS 播放完成事件触发: $utteranceId, 实际耗时: ${elapsedMs + 60}ms');
          break;
        }

        // 2. 兜底逻辑：如果一直没收到事件，但已经超过了合理的兜底时长
        if (elapsedMs >= fallbackDurationMs) {
          debugPrint('🗣️ [AudioDiag] TTS超时(兜底): id=$utteranceId, 已等待=${elapsedMs}ms');
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
      if (generation == _currentGeneration) {
        _isSpeaking = false;
      }
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

  /// 立即停止当前正在播放的声音，并使任何等待/排队中的发音失效。
  Future<void> stop() async {
    _currentGeneration++;
    _stopRequested = true;
    _isSpeaking = false;

    if (!PlatformUtils.isTtsSupported()) {
      return;
    }

    try {
      await methodChannel.invokeMethod('stop');
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
