import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/app_clock.dart';

/// 全局唯一的音频会话控制器。
///
/// **所有音频相关操作都必须通过此控制器**，包括：
/// - 单词/例句发音播放
/// - 音效播放（正确/错误提示音等）
/// - ASR 启停与音频状态机切换
///
/// ## 设计原则
///
/// 1. **Singleton** — 全局唯一实例，消除多实例间的播放器冲突
/// 2. **串行队列锁** — 全部异步操作经 [_queueLock] 串行化，根除竞态
/// 3. **统一播放器管理** — 控制器持有一个主播放器供发音/例句使用，
///    音效播放器由 SoundUtil 内部音效池管理
/// 4. **不直接暴露 SoundUtil** — 外部代码通过控制器方法间接使用 SoundUtil，
///    避免音频操作散落在各处
class StudyAudioSessionController {
  // ============================================================
  // Singleton
  // ============================================================

  static final StudyAudioSessionController _instance =
      StudyAudioSessionController._internal();

  /// 公开的单例访问器。
  static StudyAudioSessionController get instance => _instance;

  factory StudyAudioSessionController([ja.AudioPlayer? _]) => _instance;

  StudyAudioSessionController._internal()
      : _asr = Asr(),
        _audioPlayer = SoundUtil.createAudioPlayer() {
    SoundUtil.watchPlayer(_audioPlayer);
    _asr.addStateListener(_onAsrStateChange);
  }

  // ============================================================
  // Dependencies
  // ============================================================

  final Asr _asr;
  final ja.AudioPlayer _audioPlayer;
  final _SessionMutex _queueLock = _SessionMutex();
  Timer? _idleTimer;

  @visibleForTesting
  Timer? get idleTimerForTesting => _idleTimer;

  /// 是否保留麦克风保温状态（即使页面销毁或调用 stopSession，也只执行 ASR 停止而不断开麦克风物理流）
  bool keepMicrophoneWarm = false;

  /// 取消待执行的延迟释放麦克风任务
  void cancelIdleTimer() {
    keepMicrophoneWarm = false;
    if (_idleTimer != null) {
      debugPrint('⏱️ [SessionController] 取消待执行的延迟释放麦克风任务');
      _idleTimer!.cancel();
      _idleTimer = null;
    }
  }

  // ============================================================
  // Meter / Level（用于 ASR 录音音量可视化）
  // ============================================================

  final ValueNotifier<double> meterLevelNotifier =
      ValueNotifier<double>(0.0);
  StreamSubscription<double>? _meterSub;
  Timer? _meterTimer;
  double _lastMeterLevel = 0.0;
  DateTime? _lastMeterAt;
  bool _meterTickFlip = false;

  // ============================================================
  // Public API — 状态查询
  // ============================================================

  AudioMode get activeMode => SoundUtil.activeMode;
  String get activeSessionCategory => SoundUtil.activeSessionCategory;

  /// 主播放器引用。仅用于极少数需要直接操作播放器的场景。
  ja.AudioPlayer get primaryPlayer => _audioPlayer;

  // ============================================================
  // Public API — 发音/例句播放（串行化）
  // ============================================================

  /// 播放单词发音。
  Future<void> playWordSound(WordVo word,
      {Future<void>? preWaitFuture}) {
    cancelIdleTimer();
    return _queueLock.protect(() async {
      _unsubscribeMeter();
      await SoundUtil.playPronounceSound2(word, _audioPlayer,
          preWaitFuture: preWaitFuture);
    });
  }

  /// 播放例句发音。
  Future<void> playSentenceSound(String digest,
      {double speed = 1.0, Future<void>? preWaitFuture}) {
    cancelIdleTimer();
    return _queueLock.protect(() async {
      _unsubscribeMeter();
      await SoundUtil.playSentenceSound2(digest, _audioPlayer,
          speed: speed, preWaitFuture: preWaitFuture);
    });
  }

  /// 通过拼写播放发音（内部使用一次性播放器，播放后自动释放）。
  Future<void> playWordSoundBySpell(String spell) {
    cancelIdleTimer();
    return _queueLock.protect(() async {
      await SoundUtil.playPronounceSoundBySpell(spell);
    });
  }

  /// 原子化地播放单词发音 + 例句。
  Future<void> playWordAndSentence(
    WordVo word, {
    required String? sentenceDigest,
    required bool playWord,
    required bool playSentence,
    required bool isSpeakMode,
  }) async {
    cancelIdleTimer();
    _logPlayerState('playWordAndSentence.enter');
    debugPrint(
      '🕵️ [AudioDiag] playWordAndSentence | '
      'word=${word.spell} playWord=$playWord playSentence=$playSentence '
      'isSpeakMode=$isSpeakMode'
    );
    return _queueLock.protect(() async {
      if (!playWord && !playSentence) return;
      _unsubscribeMeter();

      // 软复位播放器：静音 → pause → seek(0)。stop() 在 iOS 上会触发
      // _setPlatformActive(false) 导致会话被 deactivated，并可能引发
      // AVPlayer 重放缓冲区尾部（双连播放），因此统一使用 pause。
      // 若播放器处于 buffering 状态，后续 playSoundByUrl 的 reset 块会
      // 条件检测并用 stop() 硬复位；此处用 pause 保持会话活跃，
      // 配合 transitTo(playback) 的 force:true 强制重激活确保会话正常。
      try {
        if (_audioPlayer.playing) {
          await _audioPlayer.setVolume(0.0);
        }
        await _audioPlayer.pause();
        await _audioPlayer.seek(Duration.zero);
      } catch (_) {}

      final sessionFuture = SoundUtil.transitTo(
        AudioMode.playback,
        asrInstance: _asr,
        hotPlayback: false,
      );
      SoundUtil.watchPlayer(_audioPlayer);

      if (playWord) {
        await SoundUtil.playPronounceSound2(word, _audioPlayer,
            preWaitFuture: sessionFuture);
        if (playSentence && sentenceDigest != null) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      if (playSentence && sentenceDigest != null) {
        await SoundUtil.playSentenceSound2(sentenceDigest, _audioPlayer);
      }
      _logPlayerState('playWordAndSentence.end');
    });
  }

  // ============================================================
  // Public API — 音效（不阻塞队列，使用独立音效池）
  // ============================================================

  /// 播放音效（异步、非阻塞、使用内部音效池）。
  void playSoundEffect(String fileName,
      {double speed = 1.0, double volume = 1.0}) {
    SoundUtil.playAssetSoundConcurrent(fileName, speed, volume);
  }

  void playAddSuccessSound() {
    SoundUtil.playAddSuccessSound();
  }

  /// 阻塞式播放音效（等待播放完成，使用独立音效池）。
  Future<void> playBlockingSound(String fileName,
      {double speed = 1.0, double volume = 1.0,
       int timeoutMs = 2000, int sleepAfterMs = 0}) {
    return SoundUtil.playAssetSound(fileName, speed, volume, timeoutMs, sleepAfterMs);
  }

  /// 播放音效（带最长播放时间截断）。
  Future<void> playSoundWithCut(String fileName,
      {double speed = 1.0, double volume = 1.0,
       required Duration maxPlay}) {
    return SoundUtil.playAssetSoundCut(fileName, speed, volume, maxPlay);
  }

  // ============================================================
  // Public API — ASR 会话管理（串行化）
  // ============================================================

  Future<void> startSession({
    required AsrLanguage language,
    required List<String> phrases,
    required bool isSpeakMode,
  }) async {
    cancelIdleTimer();
    return _queueLock.protect(() async {
      if (_asr.currentLanguage != language) {
        debugPrint(
          '⏱️ [SessionController] 检测到语言发生切换 (${_asr.currentLanguage?.locale} ➔ ${language.locale})，提前静默配置 Locale',
        );
        await _asr.updateLanguage(language);
      }
      if (isSpeakMode) {
        final bool isAlreadyRecord =
            SoundUtil.activeMode == AudioMode.record;
        await SoundUtil.transitTo(AudioMode.record, asrInstance: _asr);
        if (isAlreadyRecord) {
          debugPrint(
            '🔊 [SessionController] 状态机本来已是 record 保温态，执行手动热复用就绪提示音播放...',
          );
          await SoundUtil.playAsrReadyHintSoundWithCleanup();
        }
        await _asr
            .startAsr(language, phrases: phrases, playHintSound: false);
      }
    });
  }

  Future<void> stopSession({
    bool forceStopMicrophone = false,
  }) async {
    if (forceStopMicrophone && keepMicrophoneWarm) {
      if (_idleTimer != null) {
        debugPrint('⏱️ [SessionController] 重新刷新麦克风保温计时器，取消之前的任务');
        _idleTimer!.cancel();
        _idleTimer = null;
      }

      debugPrint('⏱️ [SessionController] 收到麦克风保温释放请求，延迟 10 秒物理释放...');
      final completer = Completer<void>();
      _idleTimer = Timer(const Duration(seconds: 10), () async {
        _idleTimer = null;
        keepMicrophoneWarm = false;
        try {
          await _queueLock.protect(() async {
            _unsubscribeMeter();
            debugPrint('⏱️ [SessionController] 保温延迟时间已到，开始物理释放麦克风...');
            await SoundUtil.transitTo(AudioMode.idle, asrInstance: _asr);
            await _asr.reset();
          });
          completer.complete();
        } catch (e, st) {
          completer.completeError(e, st);
        }
      });
      return completer.future;
    }

    if (forceStopMicrophone) {
      cancelIdleTimer();
    }

    return _queueLock.protect(() async {
      _unsubscribeMeter();
      if (forceStopMicrophone) {
        debugPrint(
          '⏱️ [SessionController] 物理释放麦克风与原生识别流...',
        );
        await SoundUtil.transitTo(AudioMode.idle, asrInstance: _asr);
      } else {
        debugPrint(
          '⏱️ [SessionController] 热停止 ASR 任务并保留麦克风保温...',
        );
        await _asr.stopAsr();
      }
      await _asr.reset();
    });
  }

  /// 取消当前排队中的播放任务。
  ///
  /// 1. 主播放器静音 —— 消除当前播放的输出
  /// 2. `pause() + seek(0)` 软复位播放器，避免 stop() 触发音频会话 deactivation
  /// 3. 取消串行队列锁 —— 使下一次播放可立即执行
  Future<void> cancelPlayback() async {
    _logPlayerState('cancelPlayback.enter');
    _queueLock.cancel();
    try {
      await _audioPlayer.setVolume(0.0);
      _logPlayerState('cancelPlayback.afterMute');
      await _audioPlayer.pause();
      await _audioPlayer.seek(Duration.zero);
      _logPlayerState('cancelPlayback.afterStop');
    } catch (_) {}
  }

  void _logPlayerState(String tag) {
    debugPrint(
      '🕵️ [AudioDiag] $tag | '
      'processingState=${_audioPlayer.processingState} '
      'playing=${_audioPlayer.playing} '
      'volume=${_audioPlayer.volume} '
      'speed=${_audioPlayer.speed} '
      'playerId=${_audioPlayer.hashCode}'
    );
  }

  // ============================================================
  // Public API — 生命周期与初始化
  // ============================================================

  /// 配置音频会话（应用启动时调用一次即可）。
  Future<void> configureSession() {
    cancelIdleTimer();
    return _queueLock.protect(() => SoundUtil.configureAudioSession());
  }

  /// 预热音效池。
  Future<void> prewarm() {
    return _queueLock.protect(() => SoundUtil.prewarmCoreSounds());
  }

  /// 预拉取音频 URL 到缓存。
  void prefetchSounds(List<String> urls) {
    SoundUtil.prefetchSounds(urls);
  }

  /// 播放 AI 故事英文配音。
  Future<void> playAiStoryEnSound(String wordsHash) {
    cancelIdleTimer();
    return _queueLock.protect(() => SoundUtil.playAiStoryEnSound(wordsHash));
  }

  /// 播放 AI 故事中文配音。
  Future<void> playAiStoryCnSound(String wordsHash) {
    cancelIdleTimer();
    return _queueLock.protect(() => SoundUtil.playAiStoryCnSound(wordsHash));
  }

  /// 销毁控制器（应用退出时调用）。
  Future<void> dispose() {
    cancelIdleTimer();
    _asr.removeStateListener(_onAsrStateChange);
    _unsubscribeMeter();
    meterLevelNotifier.dispose();
    SoundUtil.unwatchPlayer(_audioPlayer);
    try {
      _audioPlayer.setVolume(0.0);
      _audioPlayer.stop();
      // ignore: empty_catches
    } catch (_) {}
    return _audioPlayer.dispose();
  }

  // ============================================================
  // Private
  // ============================================================

  void _onAsrStateChange(AsrState state) {
    if (state == AsrState.started) {
      _subscribeMeter();
    } else if (state == AsrState.stopped) {
      _unsubscribeMeter();
    }
  }

  void _subscribeMeter() {
    _unsubscribeMeter();
    _meterSub = _asr.getOrCreateMeterSubscription((level) {
      _lastMeterLevel = level.clamp(0.0, 1.0);
      _lastMeterAt = AppClock.now();
    });
    _meterTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final now = AppClock.now();
      final active =
          _lastMeterAt != null &&
          now.difference(_lastMeterAt!).inMilliseconds < 150;
      final v = (active ? _lastMeterLevel : 0.0).clamp(0.0, 1.0);
      _meterTickFlip = !_meterTickFlip;
      final bump = _meterTickFlip ? 1e-6 : -1e-6;
      meterLevelNotifier.value = (v + bump).clamp(0.0, 1.0);
    });
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

/// 内部轻量级串行互斥队列锁。
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

  /// 取消当前队列链，后续 [protect] 调用将在一个新链上立即执行。
  void cancel() {
    _chain = Future.value();
  }
}
