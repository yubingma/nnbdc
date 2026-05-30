import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/app_clock.dart';

/// 听说评测唯一会话控制器 (StudyAudioSessionController)
/// 它高内聚地捏合了 SoundUtil 和 Asr 的底层细节，并通过内部串行队列锁（_SessionMutex）
/// 确保所有音频播放、ASR 启停和电平流管理都在单轨下串行运行，彻底阻断 Race Condition 造成的物理死锁与爆音。
class StudyAudioSessionController {
  final Asr _asr = Asr();
  final ja.AudioPlayer _audioPlayer;

  /// 唯一的串行化任务队列锁，杜绝所有物理时序竞态
  final _SessionMutex _queueLock = _SessionMutex();

  /// 暴露给 UI 渲染的音量计电平值（0.0 ~ 1.0）
  final ValueNotifier<double> meterLevelNotifier = ValueNotifier<double>(0.0);
  StreamSubscription<double>? _meterSub;
  Timer? _meterTimer;
  double _lastMeterLevel = 0.0;
  DateTime? _lastMeterAt;
  bool _meterTickFlip = false;

  StudyAudioSessionController(this._audioPlayer) {
    // 监听 ASR 状态广播：只有当 ASR 切实状态变成 started 时，才安全、延迟地建立电平订阅，
    // 彻底杜绝由于 ASR 尚未拉起而导致的电平流哑火和死锁问题。
    _asr.addStateListener(_onAsrStateChange);
  }

  void _onAsrStateChange(AsrState state) {
    if (state == AsrState.started) {
      _subscribeMeter();
    } else if (state == AsrState.stopped) {
      _unsubscribeMeter();
    }
  }

  /// 1. 开启一个听说评测会话，完成前置的语言 Locale 配置、麦克风和 Category 稳定激活
  Future<void> startSession({
    required AsrLanguage language,
    required List<String> phrases,
    required bool isSpeakMode,
  }) async {
    return _queueLock.protect(() async {
      // a. 特殊优化：在启动麦克风物理流（transitTo）之前，若语言发生切换，
      //    必须先在原生层静默更新好语言。这彻底避免了在麦克风运行中动态更新 Locale 导致的原生引擎死锁。
      if (_asr.currentLanguage != language) {
        debugPrint('⏱️ [SessionController] 检测到语言发生切换 (${_asr.currentLanguage?.locale} ➔ ${language.locale})，提前静默配置 Locale');
        await _asr.updateLanguage(language);
      }

      if (isSpeakMode) {
        final bool isAlreadyRecord = SoundUtil.activeMode == AudioMode.record;
        // b. 统一状态机切换到 record 录音模式
        await SoundUtil.transitTo(AudioMode.record, asrInstance: _asr);
        if (isAlreadyRecord) {
          debugPrint('🔊 [SessionController] 状态机本来已是 record 保温态，执行手动热复用就绪提示音播放...');
          await SoundUtil.playAsrReadyHintSoundWithCleanup();
        }

        // c. 正式向 native 发起 ASR 识别指令 (playHintSound: false，因为提示音已经错峰播放过了)
        await _asr.startAsr(language, phrases: phrases, playHintSound: false);
      }
    });
  }

  /// 2. 平滑停止/暂停当前 ASR 识别任务或物理关停麦克风，释放硬件焦点
  Future<void> stopSession({bool forceStopMicrophone = false}) async {
    return _queueLock.protect(() async {
      _unsubscribeMeter();
      if (forceStopMicrophone) {
        debugPrint('⏱️ [SessionController] 强制释放麦克风与原生识别流...');
        await SoundUtil.transitTo(AudioMode.idle, asrInstance: _asr);
      } else {
        debugPrint('⏱️ [SessionController] 热停止 ASR 任务并保留麦克风保温...');
        await _asr.stopAsr();
      }
      await _asr.reset();
    });
  }

  /// 3. 安全、原子化地播放单词发音和第一句例句（自动处理 AudioMode 切换与排空）
  Future<void> playWordAndSentence(
    WordVo word, {
    required String? sentenceDigest,
    required bool playWord,
    required bool playSentence,
    required bool isSpeakMode,
  }) async {
    return _queueLock.protect(() async {
      if (!playWord && !playSentence) return;

      // 播放声音前无条件取消电平流订阅，确保通道干净
      _unsubscribeMeter();

      // a. 切换到 playback 纯播放状态
      final sessionFuture = SoundUtil.transitTo(
        AudioMode.playback,
        asrInstance: _asr,
        hotPlayback: isSpeakMode && SoundUtil.activeSessionCategory == 'playAndRecord',
      );
      SoundUtil.watchPlayer(_audioPlayer);

      if (playWord) {
        await SoundUtil.playPronounceSound2(word, _audioPlayer, preWaitFuture: sessionFuture);
        if (playSentence && sentenceDigest != null) {
          await Future.delayed(const Duration(milliseconds: 100)); // 物理错峰排空
        }
      }

      if (playSentence && sentenceDigest != null) {
        await SoundUtil.playSentenceSound2(sentenceDigest, _audioPlayer);
      }
    });
  }

  /// 4. 彻底销毁控制器，释放所有订阅和资源
  Future<void> dispose() async {
    _asr.removeStateListener(_onAsrStateChange);
    _unsubscribeMeter();
    meterLevelNotifier.dispose();
  }

  /// 内部电平流订阅维护
  void _subscribeMeter() {
    _unsubscribeMeter(); // 无条件先彻底释放任何可能残留的旧电平订阅和 Timer

    _meterSub = _asr.getOrCreateMeterSubscription((level) {
      _lastMeterLevel = level.clamp(0.0, 1.0);
      _lastMeterAt = AppClock.now();
    });

    _meterTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final now = AppClock.now();
      final active = _lastMeterAt != null &&
          now.difference(_lastMeterAt!).inMilliseconds < 150;
      final v = (active ? _lastMeterLevel : 0.0).clamp(0.0, 1.0);

      // 强制触发重绘：在数值附近加入极小扰动，避免相等不通知
      _meterTickFlip = !_meterTickFlip;
      final bump = _meterTickFlip ? 1e-6 : -1e-6;
      meterLevelNotifier.value = (v + bump).clamp(0.0, 1.0);
    });
    debugPrint('⏱️ [SessionController] 物理电平计流订阅成功建立');
  }

  void _unsubscribeMeter() {
    _meterSub?.cancel();
    _meterSub = null;
    _meterTimer?.cancel();
    _meterTimer = null;
    meterLevelNotifier.value = 0.0;
    _lastMeterLevel = 0.0;
    _lastMeterAt = null;
  }
}

/// 内部轻量级串行互斥队列锁
class _SessionMutex {
  Future<void> _chain = Future.value();
  Future<T> protect<T>(Future<T> Function() body) {
    final completer = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        final result = await body();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    }).catchError((_) {});
    return completer.future;
  }
}
