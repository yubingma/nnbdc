import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_session/audio_session.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/pinyin.dart';
import 'package:nnbdc/util/study_config.dart';
import 'package:nnbdc/global.dart';

/// 全局唯一的音频会话控制器。
///
/// **所有音频和 ASR 录音相关的物理硬件操作都必须通过此控制器**，包括：
/// - 单词/例句发音播放
/// - 音效播放（正确/错误提示音等，使用独立的音效播放池）
/// - ASR 启停与音频状态机切换（通过声明式 Intent 自动决定保温与硬件释放）
///
/// ## 设计原则
///
/// 1. **Singleton** — 全局唯一实例，消除多实例间的播放器冲突
/// 2. **串行队列锁** — 全部异步操作经 [_queueLock] 串行化，根除竞态
/// 3. **整合状态中枢** — 接管原 SoundUtil 的全部状态机、播放器观察池与淡入淡出防护，消除双中心耦合
/// 4. **物理资源防撞车** — 封装 Soft-Mute, Early-Exit 与 Category 重试机制，根除 iOS 爆音与 561017449 报错
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
    _watchPlayer(_audioPlayer);
    _asrHintPlayer = SoundUtil.createAudioPlayer();
    _watchPlayer(_asrHintPlayer!);
    _asr.addStateListener(_onAsrStateChange);
  }

  // ============================================================
  // Dependencies & States (Consolidated from SoundUtil)
  // ============================================================

  final Asr _asr;
  final ja.AudioPlayer _audioPlayer;
  ja.AudioPlayer? _asrHintPlayer;
  final _SessionMutex _queueLock = _SessionMutex();
  Timer? _idleTimer;

  @visibleForTesting
  Timer? get idleTimerForTesting => _idleTimer;

  DateTime? _lastAsrStartAt;

  /// 是否保留麦克风保温状态（即使页面销毁或调用 stopSession，也只执行 ASR 停止而不断开麦克风物理流）
  bool keepMicrophoneWarm = false;
  Object? _activeNotifier;

  void registerNotifier(Object notifier) {
    _activeNotifier = notifier;
    debugPrint('⏱️ [SessionController] 注册新的活跃 Notifier: $notifier');
  }

  /// 取消待执行的延迟释放麦克风任务
  void cancelIdleTimer() {
    keepMicrophoneWarm = false;
    if (_idleTimer != null) {
      debugPrint('⏱️ [SessionController] 取消待执行的延迟释放麦克风任务');
      _idleTimer!.cancel();
      _idleTimer = null;
    }
  }

  // 音频状态机变量（从 SoundUtil 迁移过来）
  AudioMode _activeMode = AudioMode.idle;
  String _currentSessionCategory = 'none';
  bool _audioSessionConfigured = false;
  Future<void>? _configureFuture;

  // 播放器集合管理
  final List<ja.AudioPlayer> _watchedPlayers = [];
  final List<ja.AudioPlayer> _sfxPool = [];
  static const int _sfxPoolSize = 3;

  final Set<ja.AudioPlayer> _logicallyFinishedPlayers = {};
  final Map<ja.AudioPlayer, DateTime> _playerBusyUntil = {};
  final Map<ja.AudioPlayer, Object> _activeCutToken = {};
  final Map<ja.AudioPlayer, Object> _activeVolumeToken = {};
  final Map<ja.AudioPlayer, String> _playerLoadedAsset = {};

  // 内部锁
  final _SessionMutex _stateTransitionLock = _SessionMutex();
  final _SessionMutex _sessionLock = _SessionMutex();
  final _SessionMutex _sfxLock = _SessionMutex();

  // ============================================================
  // Meter / Level（用于 ASR 录音音量可视化）
  // ============================================================

  final ValueNotifier<double> meterLevelNotifier = ValueNotifier<double>(0.0);
  StreamSubscription<double>? _meterSub;
  Timer? _meterTimer;
  double _lastMeterLevel = 0.0;
  DateTime? _lastMeterAt;
  bool _meterTickFlip = false;

  // ============================================================
  // Public API — 状态查询与基础操作
  // ============================================================

  AudioMode get activeMode => _activeMode;
  String get activeSessionCategory => _currentSessionCategory;
  bool get isSfxPoolFullyPrewarmed => _sfxPool.length >= _sfxPoolSize;
  ja.AudioPlayer get primaryPlayer => _audioPlayer;

  @visibleForTesting
  void watchPlayer(ja.AudioPlayer player) => _watchPlayer(player);

  @visibleForTesting
  void unwatchPlayer(ja.AudioPlayer player) => _unwatchPlayer(player);

  @visibleForTesting
  set audioSessionConfigured(bool value) => _audioSessionConfigured = value;

  @visibleForTesting
  void resetForTesting() {
    _currentSessionCategory = 'none';
    _audioSessionConfigured = false;
    _activeMode = AudioMode.idle;
    _watchedPlayers.clear();
    _watchPlayer(_audioPlayer);
    if (_asrHintPlayer != null) {
      _watchPlayer(_asrHintPlayer!);
    }
    _logicallyFinishedPlayers.clear();
    _playerBusyUntil.clear();
    _activeCutToken.clear();
    _activeVolumeToken.clear();
    _playerLoadedAsset.clear();
    _configureFuture = null;
  }

  @visibleForTesting
  Future<void> usePlaybackCategory({bool force = false}) => _usePlaybackCategory(force: force);

  @visibleForTesting
  Future<void> usePlayAndRecordCategory() => _usePlayAndRecordCategory();

  @visibleForTesting
  String get currentSessionCategory => _currentSessionCategory;

  @visibleForTesting
  Set<ja.AudioPlayer> get logicallyFinishedPlayers => _logicallyFinishedPlayers;

  void _watchPlayer(ja.AudioPlayer player) {
    if (!_watchedPlayers.contains(player)) {
      _watchedPlayers.add(player);
    }
  }

  void _unwatchPlayer(ja.AudioPlayer player) {
    _watchedPlayers.remove(player);
    _logicallyFinishedPlayers.remove(player);
    _playerBusyUntil.remove(player);
    _activeCutToken.remove(player);
    _activeVolumeToken.remove(player);
    _playerLoadedAsset.remove(player);
    debugPrint('🔊 [SessionController] 已从监视名单安全移除播放器: ${player.hashCode}');
  }

  // ============================================================
  // Public API — 声明式硬件同步调度 (Declarative Hardware Synchronization)
  // ============================================================

  /// 根据业务意图声明，自动同步底层音频 Category 和麦克风物理资源。
  ///
  /// - [isInSpeakTab]：当前是否处于说 Tab（即说模式活跃）
  /// - [isAnsweringActive]：当前答题是否处于活跃期（未答完、非换词中、非手写板/键盘展开中）
  /// - [language]：若启动识别所需的 ASR 语言
  /// - [phrases]：识别热词列表
  /// - [caller]：发起同步的业务对象引用，防止老实例异步泄露抢占
  Future<void> syncHardwareIntent({
    required bool isInSpeakTab,
    required bool isAnsweringActive,
    required AsrLanguage language,
    required List<String> phrases,
    Object? caller,
  }) async {
    if (caller != null && _activeNotifier != null && caller != _activeNotifier) {
      debugPrint('⏱️ [SessionController] 忽略来自老实例 $caller 的 syncHardwareIntent 请求，当前活跃为 $_activeNotifier');
      return;
    }

    debugPrint('💡 [SessionController] 收到声明式硬件意图同步: isInSpeakTab=$isInSpeakTab, isAnsweringActive=$isAnsweringActive');

    if (isInSpeakTab) {
      if (isAnsweringActive) {
        // 1. 需要开始识别答题：启动/恢复 ASR，确保物理麦克风开启
        await startSession(
          language: language,
          phrases: phrases,
          isSpeakMode: true,
        );
      } else {
        // 2. 虽在说模式，但处于非答题暂态（如已答对、换词中、手写板展开）：热停止 ASR 任务并挂起，但保持麦克风保温稳定
        final shouldKeepWarm = true; 
        await stopSession(forceStopMicrophone: !shouldKeepWarm);
      }
    } else {
      // 3. 不在说模式下，或切换到了选择题 Tab：强制物理冷释放麦克风，避免硬件泄漏
      await stopSession(forceStopMicrophone: true);
    }
  }

  // ============================================================
  // Public API — 发音/例句播放（串行化）
  // ============================================================

  /// 播放单词发音。
  Future<void> playWordSound(WordVo word, {Future<void>? preWaitFuture}) {
    cancelIdleTimer();
    return _queueLock.protect(() async {
      _unsubscribeMeter();
      final sessionFuture = transitTo(AudioMode.playback);
      await _playPronounceSound2(word, _audioPlayer,
          preWaitFuture: preWaitFuture ?? sessionFuture);
    });
  }

  /// 播放例句发音。
  Future<void> playSentenceSound(String digest,
      {double speed = 1.0, Future<void>? preWaitFuture}) {
    cancelIdleTimer();
    return _queueLock.protect(() async {
      _unsubscribeMeter();
      final sessionFuture = transitTo(AudioMode.playback);
      await _playSentenceSound2(digest, _audioPlayer,
          speed: speed, preWaitFuture: preWaitFuture ?? sessionFuture);
    });
  }

  /// 通过拼写播放发音（内部使用一次性播放器，播放后自动释放）。
  Future<void> playWordSoundBySpell(String spell) {
    cancelIdleTimer();
    return _queueLock.protect(() async {
      final player = SoundUtil.createAudioPlayer();
      _watchPlayer(player);
      await playSoundByUrl(Util.getWordSoundUrl(spell), player, true);
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

      try {
        if (_audioPlayer.playing) {
          await _audioPlayer.setVolume(0.0);
        }
        await _audioPlayer.pause();
        await _audioPlayer.seek(Duration.zero);
      } catch (_) {}

      final sessionFuture = transitTo(AudioMode.playback);
      _watchPlayer(_audioPlayer);

      if (playWord) {
        await _playPronounceSound2(word, _audioPlayer,
            preWaitFuture: sessionFuture);
        if (playSentence && sentenceDigest != null) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      if (playSentence && sentenceDigest != null) {
        await _playSentenceSound2(sentenceDigest, _audioPlayer);
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
    _playAssetSoundConcurrent(fileName, speed, volume);
  }

  void playAddSuccessSound() {
    unawaited(_playAssetSoundConcurrent('bubble-pop.wav', 1.0, 0.6));
  }

  /// 阻塞式播放音效（等待播放完成，使用独立音效池）。
  Future<void> playBlockingSound(String fileName,
      {double speed = 1.0, double volume = 1.0,
       int timeoutMs = 2000, int sleepAfterMs = 0}) {
    return _playAssetSound(fileName, speed, volume, timeoutMs, sleepAfterMs);
  }

  /// 播放音效（带最长播放时间截断）。
  Future<void> playSoundWithCut(String fileName,
      {double speed = 1.0, double volume = 1.0,
       required Duration maxPlay}) {
    return _playAssetSoundCut(fileName, speed, volume, maxPlay);
  }

  // ============================================================
  // ASR & Hardware Session Core (Migrated from SoundUtil)
  // ============================================================

  Future<void> startSession({
    required AsrLanguage language,
    required List<String> phrases,
    required bool isSpeakMode,
  }) async {
    final now = AppClock.now();
    if (_lastAsrStartAt != null &&
        now.difference(_lastAsrStartAt!).inMilliseconds < 600) {
      debugPrint('⚡ [SessionController] 拦截 startSession：与上次启动时间间隔过近 (${now.difference(_lastAsrStartAt!).inMilliseconds}ms)，防止串行二次启动颤音');
      return;
    }
    _lastAsrStartAt = now;

    cancelIdleTimer();
    return _queueLock.protect(() async {
      if (_asr.currentLanguage != language) {
        debugPrint(
          '⏱️ [SessionController] 检测到语言发生切换 (${_asr.currentLanguage?.locale} ➔ ${language.locale})，提前静默配置 Locale',
        );
        await _asr.updateLanguage(language);
      }
      if (isSpeakMode) {
        final bool isAlreadyRecord = _activeMode == AudioMode.record;
        await transitTo(AudioMode.record);
        if (isAlreadyRecord) {
          debugPrint(
            '🔊 [SessionController] 状态机本来已是 record 保温态，执行手动热复用就绪提示音播放...',
          );
          await _playAsrReadyHintSoundWithCleanup();
        }
        await _asr.startAsr(language, phrases: phrases, playHintSound: false);
      }
    });
  }

  Future<void> stopSession({
    bool forceStopMicrophone = false,
    Object? caller,
  }) async {
    if (caller != null && _activeNotifier != null && caller != _activeNotifier) {
      debugPrint('⏱️ [SessionController] 忽略来自老实例 $caller 的 stopSession 请求，当前活跃实例为 $_activeNotifier');
      return;
    }
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
            await transitTo(AudioMode.idle);
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
        await transitTo(AudioMode.idle);
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
  Future<void> cancelPlayback() async {
    _logPlayerState('cancelPlayback.enter');
    _queueLock.cancel();
    try {
      await _audioPlayer.setVolume(0.0);
      _logPlayerState('cancelPlayback.afterMute');
      final needHardStop = _audioPlayer.playing ||
          _audioPlayer.processingState == ja.ProcessingState.buffering ||
          _audioPlayer.processingState == ja.ProcessingState.loading;
      if (needHardStop) {
        await _audioPlayer.stop().timeout(const Duration(milliseconds: 500));
      } else {
        await _audioPlayer.pause().timeout(const Duration(milliseconds: 500));
      }
      await _audioPlayer.seek(Duration.zero).timeout(const Duration(milliseconds: 500));
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
  // State Machine Transitions & Re-configuration
  // ============================================================

  /// 全局唯一的音频工作状态机转换网关（原子化、串行化、硬件防撞车）
  Future<void> transitTo(AudioMode targetMode) {
    return _stateTransitionLock.protect(() async {
      var finalTargetMode = targetMode;
      if (targetMode == AudioMode.record && !PlatformUtils.isAsrSupported()) {
        finalTargetMode = AudioMode.playback;
      }
 
      if (_activeMode == finalTargetMode) {
        if (finalTargetMode == AudioMode.playback) {
          await _waitForAllPlayers();
          final bool isCategoryChanged = _currentSessionCategory != 'playback';
          if (isCategoryChanged) {
            await _usePlaybackCategory(force: true);
          }
          final delayMs = isCategoryChanged ? 150 : 80;
          await Future.delayed(Duration(milliseconds: delayMs));
        }
        return;
      }
 
      final sw = Stopwatch()..start();
      debugPrint('🔊 [AudioEngine] 状态机开始转换: $_activeMode ➔ $finalTargetMode');

      try {
        switch (finalTargetMode) {
          case AudioMode.playback:
            await _asr.stopMicrophone();
            await _cleanupEarlyExitPlayers();
            
            final bool isCategoryChanged = _currentSessionCategory != 'playback';
            await _usePlaybackCategory(force: false);
            final delayMs = isCategoryChanged ? 150 : 80;
            await Future.delayed(Duration(milliseconds: delayMs));
            break;
 
          case AudioMode.record:
            await _cleanupEarlyExitPlayers();
            
            final bool isColdStart = _currentSessionCategory != 'playAndRecord';
            await _usePlayAndRecordCategory();
            await _asr.startMicrophone();
            
            final delayMs = isColdStart ? 100 : 60;
            debugPrint('⏱️ [AudioEngine] 麦克风物理通道已激活 (${isColdStart ? "冷启动" : "热复用"})，错峰延迟 ${delayMs}ms 稳定时钟...');
            await Future.delayed(Duration(milliseconds: delayMs));
            await _playAsrReadyHintSound();
            break;
 
          case AudioMode.idle:
            await _asr.stopMicrophone();
            await _cleanupEarlyExitPlayers();
            if (_currentSessionCategory != 'playback') {
              _currentSessionCategory = 'none';
            }
            break;
        }
        
        _activeMode = finalTargetMode;
        debugPrint('🔊 [AudioEngine] 状态机转换成功: ➔ $_activeMode，总耗时: ${sw.elapsedMilliseconds}ms');
      } catch (e, st) {
        Global.logger.e('🔊 [AudioEngine] 状态机转换异常，物理熔断降级: $e', error: e, stackTrace: st);
        try {
          await _asr.stopMicrophone();
        } catch (_) {}
        try {
          await _cleanupEarlyExitPlayers();
        } catch (_) {}
        _activeMode = AudioMode.idle;
      }
    });
  }

  /// 强制重新配置音频会话（一般在用户修改了混音设置后调用以即时生效）
  Future<void> forceReconfigureSession() async {
    return _queueLock.protect(() async {
      _audioSessionConfigured = false;
      final category = _currentSessionCategory;
      if (category == 'playAndRecord') {
        _currentSessionCategory = 'none';
        await _usePlayAndRecordCategory();
      } else {
        await _usePlaybackCategory(force: true);
      }
      _audioSessionConfigured = true;
    });
  }

  /// 配置全局音频会话
  Future<void> configureSession() {
    cancelIdleTimer();
    if (_audioSessionConfigured) return Future.value();
    _configureFuture ??= _doConfigureAudioSession();
    return _configureFuture!;
  }

  Future<void> _doConfigureAudioSession() async {
    try {
      if (_currentSessionCategory != 'playAndRecord') {
        await _usePlaybackCategory();
      }
      _audioSessionConfigured = true;
      _logicallyFinishedPlayers.clear();
      Global.logger.i('StudyAudioSessionController: 全局音频会话配置完成');
      unawaited(prewarm());
      prewarmPinyin();
    } catch (e) {
      Global.logger.e('StudyAudioSessionController: 配置全局音频会话失败: $e');
    } finally {
      _configureFuture = null;
    }
  }

  Future<void> _usePlaybackCategory({bool force = false}) {
    return _sessionLock.protect(() async {
      if (PlatformUtils.isWeb) return;

      if (_asr.state == AsrState.started || _asr.state == AsrState.stopping) {
        debugPrint('⚠️ [SessionController] 拦截 usePlaybackCategory：ASR 仍处于活动中，跳过 Category 切换以防 iOS 优先级死锁。');
        return;
      }

      await _cleanupEarlyExitPlayers();
      if (_currentSessionCategory == 'playback' && !force) return;

      final sw = Stopwatch()..start();
      _logAudioState('会话切换前(→playback)');
      await _waitForAllPlayers();
      await _configurePlaybackSession(retryCount: 0, totalSw: sw);
    });
  }

  Future<void> _configurePlaybackSession({required int retryCount, required Stopwatch totalSw}) async {
    try {
      if (retryCount > 0) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final mixWithOthers = StudyConfig.fromCurrentUser().mixWithOthersForIos;
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: mixWithOthers
            ? AVAudioSessionCategoryOptions.mixWithOthers
            : AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      )).timeout(const Duration(milliseconds: 1000));
      _currentSessionCategory = 'playback';
      debugPrint('⏱️ [Latency-Sound] Session 切换到 playback 完成，耗时: ${totalSw.elapsedMilliseconds}ms');
      _logAudioState('会话切换完成(→playback ${totalSw.elapsedMilliseconds}ms)');
    } catch (e) {
      final errStr = e.toString();
      final isPriorityError = errStr.contains('561017449') ||
          errStr.contains('InsufficientPriority') ||
          errStr.contains('!pri');
      if (isPriorityError && retryCount < 3) {
        debugPrint('🔊 [SessionController] 切换 playback 遇到 InsufficientPriority，将重试 (${retryCount + 1}/3)');
        return _configurePlaybackSession(retryCount: retryCount + 1, totalSw: totalSw);
      }
      Global.logger.e('StudyAudioSessionController: 切换播放模式失败 (retryCount=$retryCount): $e');
      rethrow;
    }
  }

  Future<void> _usePlayAndRecordCategory() {
    return _sessionLock.protect(() async {
      if (PlatformUtils.isWeb) return;
      await _cleanupEarlyExitPlayers();
      if (_currentSessionCategory == 'playAndRecord') return;

      final sw = Stopwatch()..start();
      _logAudioState('会话切换前(→playAndRecord)');
      await _waitForAllPlayers();
      await _configurePlayAndRecordSession(retryCount: 0, totalSw: sw);
    });
  }

  Future<void> _configurePlayAndRecordSession({required int retryCount, required Stopwatch totalSw}) async {
    try {
      if (retryCount > 0) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final mixWithOthers = StudyConfig.fromCurrentUser().mixWithOthersForIos;
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
            (mixWithOthers ? AVAudioSessionCategoryOptions.mixWithOthers : AVAudioSessionCategoryOptions.none) |
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowAirPlay |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      )).timeout(const Duration(milliseconds: 1000));
      _currentSessionCategory = 'playAndRecord';
      debugPrint('⏱️ [Latency-Sound] Session 切换到 playAndRecord 完成，总耗时: ${totalSw.elapsedMilliseconds}ms');
      _logAudioState('会话切换完成(→playAndRecord ${totalSw.elapsedMilliseconds}ms)');
    } catch (e) {
      final errStr = e.toString();
      final isPriorityError = errStr.contains('561017449') ||
          errStr.contains('InsufficientPriority') ||
          errStr.contains('!pri');
      if (isPriorityError && retryCount < 3) {
        debugPrint('🔊 [SessionController] 切换 playAndRecord 遇到 InsufficientPriority，将重试 (${retryCount + 1}/3)');
        return _configurePlayAndRecordSession(retryCount: retryCount + 1, totalSw: totalSw);
      }
      Global.logger.e('StudyAudioSessionController: 切换为录放模式失败 (retryCount=$retryCount): $e');
      rethrow;
    }
  }

  // ============================================================
  // Playback Control Core (Migrated from SoundUtil)
  // ============================================================

  Future<void> playSoundByUrl(String soundUrl, ja.AudioPlayer player, bool disposeWhenFinish,
      {int loadTimeoutMs = 10000, int playTimeoutMs = 20000, double speed = 1.0, Future<void>? preWaitFuture}) async {
    if (PlatformUtils.isTesting) return;
    final totalSw = Stopwatch()..start();
    debugPrint('🕵️ [AudioDiag] playSoundByUrl.enter | url=$soundUrl');
    try {
      if (!_audioSessionConfigured) await configureSession();
      if (PlatformUtils.isWeb) await _ensureWebAudioUnlocked();

      if (preWaitFuture != null) {
        final waitSw = Stopwatch()..start();
        await preWaitFuture;
        debugPrint('⏱️ [Latency-Sound] 等待并行 Session 切换完成，实耗: ${waitSw.elapsedMilliseconds}ms');
      }

      try {
        _logicallyFinishedPlayers.remove(player);
        await player.setVolume(0.0);
        final needHardStop = player.playing ||
            player.processingState == ja.ProcessingState.buffering ||
            player.processingState == ja.ProcessingState.loading ||
            player.processingState == ja.ProcessingState.completed;
        if (needHardStop) {
          final isCompleted = player.processingState == ja.ProcessingState.completed;
          await player.stop();
          if (isCompleted) {
            await Future.delayed(const Duration(milliseconds: 30));
          }
        } else {
          await player.pause();
        }
        await player.seek(Duration.zero);
      } catch (_) {}

      final loadSw = Stopwatch()..start();
      if (PlatformUtils.isWeb) {
        await player.setUrl(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
      } else {
        final cacheManager = DefaultCacheManager();
        Future<bool> tryLoadFromCache(String filePath) async {
          try {
            await player.setAudioSource(ja.AudioSource.uri(Uri.file(filePath)))
                .timeout(Duration(milliseconds: loadTimeoutMs));
            return player.processingState == ja.ProcessingState.ready ||
                   player.processingState == ja.ProcessingState.loading;
          } catch (_) {}
          return false;
        }

        Future<bool> tryLoadFromUrl(String url) async {
          try {
            await player.setUrl(url).timeout(Duration(milliseconds: loadTimeoutMs));
            return player.processingState == ja.ProcessingState.ready ||
                   player.processingState == ja.ProcessingState.loading ||
                   player.processingState == ja.ProcessingState.buffering;
          } catch (_) {}
          return false;
        }

        FileInfo? fileInfo = await cacheManager.getFileFromCache(soundUrl);
        final String targetFilePath = fileInfo?.file.path ?? '';
        bool loaded = false;
        if (targetFilePath.isNotEmpty && await File(targetFilePath).exists()) {
          loaded = await tryLoadFromCache(targetFilePath);
        }
        if (!loaded) {
          loaded = await tryLoadFromUrl(soundUrl);
        }
        if (!loaded) {
          throw Exception('Failed to load audio source.');
        }
      }
      
      debugPrint('⏱️ [Latency-Sound] 资源加载耗时: ${loadSw.elapsedMilliseconds}ms');
      await player.setSpeed(speed);

      final volumeToken = Object();
      _activeVolumeToken[player] = volumeToken;
      await player.setVolume(0.015);

      bool hasStartedPlaying = false;
      final playCompletedFuture = player.playerStateStream
          .firstWhere((state) {
            if (state.playing) {
              hasStartedPlaying = true;
            }
            return state.processingState == ja.ProcessingState.completed ||
                   state.processingState == ja.ProcessingState.idle ||
                   (hasStartedPlaying && !state.playing);
          })
          .timeout(Duration(milliseconds: playTimeoutMs));

      playCompletedFuture.catchError((_) => player.playerState);

      final playSw = Stopwatch()..start();
      unawaited(player.play().catchError((_) {}));

      // Volume Fade-in
      unawaited(() async {
        try {
          final steps = [0.04, 0.08, 0.15, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0];
          for (var targetVol in steps) {
            await Future.delayed(const Duration(milliseconds: 6));
            if (_activeVolumeToken[player] != volumeToken) return;
            await player.setVolume(targetVol);
          }
        } catch (_) {}
      }());

      if (player.processingState != ja.ProcessingState.completed &&
          player.processingState != ja.ProcessingState.idle) {
        await playCompletedFuture;
      }

      _logicallyFinishedPlayers.add(player);
      debugPrint('⏱️ [Latency-Sound] 播放完成，耗时: ${playSw.elapsedMilliseconds}ms');
      Global.logger.d('🔊 [SessionController] playSoundByUrl 结束，总逻辑耗时: ${totalSw.elapsedMilliseconds}ms');
    } catch (e, st) {
      _logicallyFinishedPlayers.add(player);
      final errStr = e.toString();
      final isAbort = errStr.contains('Connection aborted') ||
                      errStr.contains('abort') ||
                      errStr.contains('Loading interrupted');
      if (isAbort) {
        Global.logger.i('🔊 [SessionController] 播放中止: $soundUrl');
      } else {
        Global.logger.e('播放异常: $soundUrl', error: e, stackTrace: st);
      }
    } finally {
      if (disposeWhenFinish) {
        Future.delayed(const Duration(seconds: 2), () {
          try {
            _unwatchPlayer(player);
            player.dispose().catchError((_) {});
          } catch (_) {}
        });
      }
    }
  }

  // ============================================================
  // Sound Effects & Pool Management (Migrated from SoundUtil)
  // ============================================================

  /// 预热音效池。
  Future<void> prewarm() async {
    if (PlatformUtils.isWeb || PlatformUtils.isTesting) return;
    for (int i = 0; i < _sfxPoolSize; i++) {
      if (_sfxPool.length <= i) {
        try {
          await Future.delayed(const Duration(milliseconds: 50));
          final player = SoundUtil.createAudioPlayer();
          _sfxPool.add(player);
          _watchPlayer(player);
          debugPrint('🔊 [SessionController] 音效池播放器 $i 初始化成功');
        } catch (e) {
          debugPrint('🔊 [SessionController] 音效池播放器 $i 初始化失败: $e');
        }
      }
    }

    final hintPlayer = _asrHintPlayer;
    if (hintPlayer != null) {
      try {
        const assetPath = 'assets/audio/asr_ready_hint.wav';
        if (_playerLoadedAsset[hintPlayer] != assetPath) {
          await hintPlayer.setAsset(assetPath);
          _playerLoadedAsset[hintPlayer] = assetPath;
          debugPrint('🔊 [SessionController] ASR 提示音常驻播放器预热成功');
        }
      } catch (e) {
        debugPrint('🔊 [SessionController] ASR 提示音常驻播放器预热失败: $e');
      }
    }
  }

  void prefetchSounds(List<String> urls) {
    SoundUtil.prefetchSounds(urls);
  }

  Future<void> _playAssetSound(
      String soundFileName, double speed, double volume, int timeoutInMilliSeconds, int sleepAfterPlayInMilliSeconds) async {
    try {
      final player = await _getAvailableSfxPlayer();
      if (player == null) return;
      
      _activeCutToken.remove(player);

      final now = AppClock.now();
      final busyDuration = Duration(milliseconds: sleepAfterPlayInMilliSeconds > 0 ? sleepAfterPlayInMilliSeconds : 1000);
      _playerBusyUntil[player] = now.add(busyDuration);
      
      await player.setVolume(0.0);
      await player.stop();
      await player.seek(Duration.zero);
      await player.setSpeed(speed);
      
      final assetPath = 'assets/audio/$soundFileName';
      final bool isSameAsset = _playerLoadedAsset[player] == assetPath;
      if (!isSameAsset) {
        await player.setAsset(assetPath).timeout(Duration(milliseconds: timeoutInMilliSeconds));
        _playerLoadedAsset[player] = assetPath;
      }
      await player.setVolume(volume);
      _logicallyFinishedPlayers.remove(player);

      bool hasStartedPlaying = false;
      final playCompletedFuture = player.playerStateStream
          .firstWhere((state) {
            if (state.playing) {
              hasStartedPlaying = true;
            }
            return state.processingState == ja.ProcessingState.completed ||
                   state.processingState == ja.ProcessingState.idle ||
                   (hasStartedPlaying && !state.playing);
          })
          .timeout(Duration(milliseconds: timeoutInMilliSeconds));

      playCompletedFuture.catchError((_) => player.playerState);
      unawaited(player.play().catchError((_) {}));

      unawaited(() async {
        try {
          await playCompletedFuture;
        } catch (_) {}
        _logicallyFinishedPlayers.add(player);
      }());
      
      if (sleepAfterPlayInMilliSeconds > 0) {
        await Future.delayed(Duration(milliseconds: sleepAfterPlayInMilliSeconds));
      }
    } catch (e) {
      debugPrint('🔊 [SessionController] playAssetSound 出错: $soundFileName, $e');
    }
  }

  Future<void> _playAssetSoundCut(String soundFileName, double speed, double volume, Duration maxPlay) async {
    try {
      final player = await _getAvailableSfxPlayer();
      if (player == null) return;
      
      final now = AppClock.now();
      _playerBusyUntil[player] = now.add(maxPlay + const Duration(milliseconds: 100));
      
      await player.setVolume(0.0);
      await player.stop();
      await player.seek(Duration.zero);
      await player.setSpeed(speed);
      
      final assetPath = 'assets/audio/$soundFileName';
      final bool isSameAsset = _playerLoadedAsset[player] == assetPath;
      if (!isSameAsset) {
        await player.setAsset(assetPath);
        _playerLoadedAsset[player] = assetPath;
      }
      await player.setVolume(volume);
      unawaited(player.play());
      
      final token = Object();
      _activeCutToken[player] = token;
      Future.delayed(maxPlay, () async {
        try {
          if (_activeCutToken[player] == token && player.playing) {
            await player.setVolume(0.0);
            await player.stop();
          }
        } catch (_) {}
      });
    } catch (e) {
      Global.logger.w('playAssetSoundCut 失败: $soundFileName, $e');
    }
  }

  Future<void> _playAsrReadyHintSound() async {
    final player = _asrHintPlayer;
    if (player == null) return;
    try {
      _activeVolumeToken[player] = Object();
      await player.setVolume(0.2);
      await player.stop();
      await player.seek(Duration.zero);
      _logicallyFinishedPlayers.remove(player);
      unawaited(player.play().catchError((_) {}));
      _playerBusyUntil[player] = AppClock.now().add(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('🔊 [SessionController] 极速播放 ASR 提示音出错: $e');
    }
  }

  Future<void> _playAsrReadyHintSoundWithCleanup() async {
    await _cleanupEarlyExitPlayers();
    await _playAsrReadyHintSound();
  }

  Future<ja.AudioPlayer?> _getAvailableSfxPlayer() {
    return _sfxLock.protect(() async {
      if (!_audioSessionConfigured) {
        await configureSession();
      }
      if (_sfxPool.length < _sfxPoolSize) {
        await prewarm();
      }
      if (_sfxPool.isEmpty) return null;
      
      final now = AppClock.now();
      ja.AudioPlayer? bestPlayer;
      
      for (var player in _sfxPool) {
        final busyUntil = _playerBusyUntil[player];
        if (!player.playing && (busyUntil == null || now.isAfter(busyUntil))) {
          _logSfxAlloc('空闲优先', player);
          return player;
        }
      }

      for (var player in _sfxPool) {
        final busyUntil = _playerBusyUntil[player];
        if (busyUntil == null || now.isAfter(busyUntil)) {
          _logSfxAlloc('busy过期', player);
          return player;
        }
      }
      
      DateTime oldestBusy = DateTime(3000);
      for (var player in _sfxPool) {
        final busyUntil = _playerBusyUntil[player] ?? DateTime(0);
        if (busyUntil.isBefore(oldestBusy)) {
          oldestBusy = busyUntil;
          bestPlayer = player;
        }
      }

      final fallback = bestPlayer ?? _sfxPool[0];
      _logSfxAlloc('兜底(池满)', fallback);
      return fallback;
    });
  }

  Future<void> _playAssetSoundConcurrent(String soundFileName, double speed, double volume) async {
    await _playAssetSound(soundFileName, speed, volume, 4000, 0);
  }

  // ============================================================
  // Inter-Module Adaptations & Cleanups
  // ============================================================

  Future<void> _playPronounceSound2(WordVo word, ja.AudioPlayer player, {Future<void>? preWaitFuture}) async {
    var soundUrl = Util.getWordSoundUrl(word.spell, word: word);
    await playSoundByUrl(soundUrl, player, false, preWaitFuture: preWaitFuture);
  }
  
  Future<void> _playSentenceSound2(String englishDigest, ja.AudioPlayer player, {double speed = 1.0, Future<void>? preWaitFuture}) async {
    var soundUrl = Util.getSentenceSoundUrl(englishDigest);
    await playSoundByUrl(soundUrl, player, false, speed: speed, preWaitFuture: preWaitFuture);
  }

  Future<void> _cleanupEarlyExitPlayers() async {
    final earlyExitPlayers = _watchedPlayers.where((p) => _logicallyFinishedPlayers.contains(p)).toList();
    if (earlyExitPlayers.isEmpty) return;

    bool hasStoppedAny = false;
    final List<ja.AudioPlayer> successfullyCleaned = [];
    for (var p in earlyExitPlayers) {
      final bool isLogicallyFinished = _logicallyFinishedPlayers.contains(p);
      final bool isPhysicallyCompleted = 
          p.processingState == ja.ProcessingState.completed ||
          p.processingState == ja.ProcessingState.idle;

      final bool shouldSkipStop = isLogicallyFinished || isPhysicallyCompleted;

      if (p.playing) {
        if (shouldSkipStop) {
          debugPrint('🔊 [AudioDiag] Skip Physical Stop: player=${p.hashCode}');
          successfullyCleaned.add(p);
        } else {
          try {
            debugPrint('🔊 [AudioDiag] EarlyExit 强制stop: player=${p.hashCode}');
            await p.setVolume(0.0);
            await p.stop().timeout(const Duration(milliseconds: 100), onTimeout: () {});
            hasStoppedAny = true;
            successfullyCleaned.add(p);
          } catch (_) {}
        }
      } else {
        successfullyCleaned.add(p);
      }
    }
    _logicallyFinishedPlayers.removeAll(successfullyCleaned);
    
    if (hasStoppedAny) {
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }

  Future<void> _waitForAllPlayers() async {
    final playersSnapshot = List<ja.AudioPlayer>.from(_watchedPlayers);
    for (var player in playersSnapshot) {
      if (_sfxPool.contains(player)) continue;
      if (_logicallyFinishedPlayers.contains(player)) continue;
      
      if (player.playing && 
          player.processingState != ja.ProcessingState.completed && 
          player.processingState != ja.ProcessingState.idle) {
        debugPrint('⏱️ [Latency-Sound] 检查到活跃播放器，进行物理级等待...');
        try {
          await player.playerStateStream.firstWhere((state) => 
              !state.playing || 
              state.processingState == ja.ProcessingState.completed || 
              state.processingState == ja.ProcessingState.idle,
              orElse: () => player.playerState)
          .timeout(const Duration(milliseconds: 1000));
        } catch (_) {}
      }
    }
  }

  void _logAudioState(String label) {
    final sfxStates = _sfxPool.map((p) {
      final busy = _playerBusyUntil[p];
      return 'p:${p.playing ? '▶' : '■'}'
          '${busy != null ? "[busy]" : ""}'
          '${_logicallyFinishedPlayers.contains(p) ? "[done]" : ""}';
    }).join(', ');
    final pp = _audioPlayer;
    final ppState = 'p:${pp.playing ? '▶' : '■'}${_logicallyFinishedPlayers.contains(pp) ? "[done]" : ""}';
    debugPrint('🔊 [AudioDiag] $label | session=$_currentSessionCategory | 发音=$ppState | 池=[$sfxStates]');
  }

  void _logSfxAlloc(String strategy, ja.AudioPlayer player) {
    debugPrint('🔊 [AudioDiag] 音效池分配: 策略=$strategy, player=${player.hashCode}');
  }

  Future<void> _ensureWebAudioUnlocked() async {
    if (!PlatformUtils.isWeb) return;
    // Mock web unlock logic inside SoundUtil helper
  }

  // AI Story
  Future<void> playAiStoryEnSound(String wordsHash) {
    cancelIdleTimer();
    return _queueLock.protect(() => playSoundByUrl(Util.getAiStoryEnSoundUrl(wordsHash), SoundUtil.createAudioPlayer(), true, loadTimeoutMs: 10000, playTimeoutMs: 120000));
  }

  Future<void> playAiStoryCnSound(String wordsHash) {
    cancelIdleTimer();
    return _queueLock.protect(() => playSoundByUrl(Util.getAiStoryCnSoundUrl(wordsHash), SoundUtil.createAudioPlayer(), true, loadTimeoutMs: 10000, playTimeoutMs: 120000));
  }

  // ============================================================
  // Lifecycle
  // ============================================================

  Future<void> dispose() {
    cancelIdleTimer();
    _asr.removeStateListener(_onAsrStateChange);
    _unsubscribeMeter();
    meterLevelNotifier.dispose();
    _unwatchPlayer(_audioPlayer);
    final hintPlayer = _asrHintPlayer;
    if (hintPlayer != null) {
      _unwatchPlayer(hintPlayer);
      try {
        hintPlayer.setVolume(0.0);
        hintPlayer.stop();
        hintPlayer.dispose().catchError((_) {});
      } catch (_) {}
    }
    try {
      _audioPlayer.setVolume(0.0);
      _audioPlayer.stop();
    } catch (_) {}
    return _audioPlayer.dispose();
  }

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
      final active = _lastMeterAt != null && now.difference(_lastMeterAt!).inMilliseconds < 150;
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

  void cancel() {
    _chain = Future.value();
  }
}
