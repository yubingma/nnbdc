import 'dart:async';
import 'dart:io';
 
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'pinyin.dart';
import 'asr.dart';
 
import 'package:flutter/foundation.dart';
import '../api/vo.dart';
 
enum AudioMode { playback, record, idle }
 
class SoundUtil {
  /// 安全创建 AudioPlayer 实例，通过子 Zone 守卫优雅拦截并消化底层可能因 uuid 冲突抛出的 PlatformException
  static ja.AudioPlayer createAudioPlayer() {
    late final ja.AudioPlayer player;
    runZonedGuarded(() {
      player = ja.AudioPlayer();
    }, (error, stack) {
      final errStr = error.toString();
      if (errStr.contains('already exists') || errStr.contains('Platform player')) {
        debugPrint('🔊 [SoundUtil] Zone 拦截到 ja.AudioPlayer() 底层重复 ID 注册异常 (安全忽略): $error');
      } else {
        throw error;
      }
    });
    return player;
  }

  static final _stateTransitionLock = _Mutex();
  static AudioMode _activeMode = AudioMode.idle;

  /// 获取当前音频状态机活跃状态
  static AudioMode get activeMode => _activeMode;

  static ja.AudioPlayer? _pronouncePlayer;
  static bool _webAudioUnlocked = false;
  static bool _webUnlockInProgress = false;
  static bool _audioSessionConfigured = false;
  static String _currentSessionCategory = 'none';

  @visibleForTesting
  static set audioSessionConfigured(bool value) => _audioSessionConfigured = value;

  /// 获取当前活跃的音频会话 Category（供业务层做冷热分轨状态智能判断）
  static String get activeSessionCategory => _currentSessionCategory;

  @visibleForTesting
  static String get currentSessionCategory => _currentSessionCategory;

  @visibleForTesting
  static List<ja.AudioPlayer> get watchedPlayers => _watchedPlayers;

  @visibleForTesting
  static Set<ja.AudioPlayer> get logicallyFinishedPlayers => _logicallyFinishedPlayers;

  /// 重置所有静态状态，仅用于测试（不 dispose 音效池播放器以避免影响其他测试）
  @visibleForTesting
  static void resetForTesting() {
    _currentSessionCategory = 'none';
    _audioSessionConfigured = false;
    _activeMode = AudioMode.idle;
    _watchedPlayers.clear();
    _logicallyFinishedPlayers.clear();
    _playerBusyUntil.clear();
    _activeCutToken.clear();
    _configureFuture = null;
  }

  /// 输出所有播放器的当前状态，供诊断音频问题使用
  static void _logAudioState(String label) {
    final sfxStates = _sfxPool.map((p) {
      final busy = _playerBusyUntil[p];
      return 'p:${p.playing ? '▶' : '■'}'
          '${busy != null ? "[busy]" : ""}'
          '${_logicallyFinishedPlayers.contains(p) ? "[done]" : ""}';
    }).join(', ');
    final pp = _pronouncePlayer;
    final ppState = pp != null
        ? 'p:${pp.playing ? '▶' : '■'}'
            '${_logicallyFinishedPlayers.contains(pp) ? "[done]" : ""}'
        : 'null';
    debugPrint('🔊 [AudioDiag] $label | session=$_currentSessionCategory '
        '| 发音=$ppState | 池=[$sfxStates]');
  }

  static void _logSfxAlloc(String strategy, ja.AudioPlayer player) {
    debugPrint('🔊 [AudioDiag] 音效池分配: 策略=$strategy, player=${player.hashCode}'
        ', 池状态=${_sfxPool.map((p) => '${p.hashCode}:${p.playing ? "▶" : "■"}').join(",")}');
  }

  static final List<ja.AudioPlayer> _sfxPool = [];
  static const int _sfxPoolSize = 3;
  static final Set<ja.AudioPlayer> _logicallyFinishedPlayers = {};
  static final Map<ja.AudioPlayer, DateTime> _playerBusyUntil = {};
  static final Map<ja.AudioPlayer, Object> _activeCutToken = {};
  
  /// 全局观察的播放器列表，用于在切换音频会话前确保它们都已播完
  static final List<ja.AudioPlayer> _watchedPlayers = [];
  
  /// 音效池分配互斥锁，防止两个音效并发抢同一播放器导致爆音/中断
  static final _sfxLock = _Mutex();

  static Future<void>? _configureFuture;
 
  /// 全局唯一的音频工作状态机转换网关（原子化、串行化、硬件防撞车）
  static Future<void> transitTo(AudioMode targetMode, {required Asr asrInstance, bool hotPlayback = false}) {
    return _stateTransitionLock.protect(() async {
      // 1. 跨平台防挂起卫士：若不支持 ASR，录音模式自动无缝降级为纯播放模式
      var finalTargetMode = targetMode;
      if (targetMode == AudioMode.record && !PlatformUtils.isAsrSupported()) {
        finalTargetMode = AudioMode.playback;
      }
 
      if (_activeMode == finalTargetMode) {
        // 若状态一致，瞬间 0ms 返回，无任何性能损耗
        return;
      }
 
      final sw = Stopwatch()..start();
      debugPrint('🔊 [AudioEngine] 状态机开始转换: $_activeMode ➔ $finalTargetMode (hotPlayback: $hotPlayback)');
 
      try {
        switch (finalTargetMode) {
          case AudioMode.playback:
            if (hotPlayback) {
              // a. 软件层热关停 ASR 识别输入流，保留麦克风物理流与 Audio Category 通道保温
              await asrInstance.stopAsr();
              // b. 强行平滑淡出（Soft-Mute）所有当前活跃的临时/音效播放器，彻底排空声卡缓冲区
              await _cleanupEarlyExitPlayers();
            } else {
              // a. 物理关闭麦克风（冷关停）
              await asrInstance.stopMicrophone();
              // b. 强行平滑淡出（Soft-Mute）所有当前活跃 of 临时/音效播放器，彻底排空声卡缓冲区
              await _cleanupEarlyExitPlayers();
              // c. 物理配置 AudioSession 为高品质 playback 模式并强行等待切换彻底确认
              await usePlaybackCategory(force: true);
            }
            break;
 
          case AudioMode.record:
            // a. 确保所有播放器处于 Soft-Mute 静音输出，防止尾音与就绪提示音/麦克风并发撞车
            await _cleanupEarlyExitPlayers();
            
            // 判断是否是物理冷启动：如果当前分类并非 playAndRecord，说明经历了物理级别的硬件重构切换
            final bool isColdStart = _currentSessionCategory != 'playAndRecord';
            
            // b. 物理配置 AudioSession 为 playAndRecord
            await usePlayAndRecordCategory();
            // c. 调用底层驱动启动麦克风物理流，等待 Mic 预热完毕
            await asrInstance.startMicrophone();
            // d. 【物理错峰阻断】：如果是物理冷启动，给底层声卡和重采样驱动留出充足的 150ms 稳定窗口以物理根除爆音；
            //    若是本已保温的热复用路径，则仅保留 10ms 极限物理时间阻断以实现瞬时就绪。
            final delayMs = isColdStart ? 150 : 10;
            debugPrint('⏱️ [AudioEngine] 麦克风物理通道已激活 (${isColdStart ? "冷启动" : "热复用"})，错峰延迟 ${delayMs}ms 稳定时钟...');
            await Future.delayed(Duration(milliseconds: delayMs));
            // e. 稳定窗口结束后，正式播放“叮”的就绪提示音
            await playAsrReadyHintSound();
            break;
 
          case AudioMode.idle:
            await asrInstance.stopMicrophone();
            await _cleanupEarlyExitPlayers();
            break;
        }
        
        _activeMode = finalTargetMode;
        debugPrint('🔊 [AudioEngine] 状态机转换成功: ➔ $_activeMode，总耗时: ${sw.elapsedMilliseconds}ms');
      } catch (e, st) {
        // 超时与异常防御卫士：一旦由于硬件突变或通道冻结抛出异常，优雅物理熔断降级，防止整个 Dart 异步协程池死锁并掐灭麦克风悬空泄漏风险
        Global.logger.e('🔊 [AudioEngine] 状态机转换发生异常，执行防死锁与防麦克风泄露终极物理熔断降级: $e', error: e, stackTrace: st);
        try {
          await asrInstance.stopMicrophone();
        } catch (_) {}
        try {
          await _cleanupEarlyExitPlayers();
        } catch (_) {}
        _activeMode = AudioMode.idle;
      }
    });
  }
 
  /// 配置全局音频会话
  static Future<void> configureAudioSession() {
    if (_audioSessionConfigured) return Future.value();
    
    _configureFuture ??= _doConfigureAudioSession();
    return _configureFuture!;
  }

  static Future<void> _doConfigureAudioSession() async {
    try {
      // 若当前已在 playAndRecord 模式（如 hot playback 保温的麦克风），
      // 跳过 playback session 切换，避免 !pri。音频在 playAndRecord 下播放正常。
      if (_currentSessionCategory != 'playAndRecord') {
        await usePlaybackCategory();
      }
      _audioSessionConfigured = true;
      // 启动时清理 _logicallyFinishedPlayers 中可能残留的旧引用
      _logicallyFinishedPlayers.clear();
      Global.logger.i('SoundUtil: 全局音频会话配置完成');
      unawaited(prewarmCoreSounds());
      prewarmPinyin();
    } catch (e) {
      Global.logger.e('SoundUtil: 配置全局音频会话失败: $e');
    } finally {
      _configureFuture = null;
    }
  }

  static final _sessionLock = _Mutex();

  /// 切换为纯播放模式
  static Future<void> usePlaybackCategory({bool force = false}) {
    return _sessionLock.protect(() async {
      if (PlatformUtils.isWeb) return;

      // 竞态防御：若 ASR 录音物理流或识别任务仍未彻底关闭，禁止强行切换音频 Category 为 playback，
      // 否则 iOS 底层会因独占流冲突强行判定优先级不足（InsufficientPriority - OSStatus 561017449）并导致 UI 线程卡死。
      if (Asr().state == AsrState.started || Asr().state == AsrState.stopping) {
        debugPrint('⚠️ [SoundUtil] 拦截 usePlaybackCategory：ASR 仍处于活动/注销中，跳过 Category 切换以防 iOS 优先级死锁。');
        return;
      }

      // 与 usePlayAndRecordCategory 对等：无论当前会话类别是否已经是 playback，
      // 只要发起切换/更新，都必须优先物理排空逻辑上已播完的 EarlyExit 播放器，
      // 确保发音尾音彻底自然淡出并物理释放硬件，根治单词发音与后续音频爆音
      await _cleanupEarlyExitPlayers();

      if (_currentSessionCategory == 'playback' && !force) return;

      final sw = Stopwatch()..start();
      _logAudioState('会话切换前(→playback)');
      debugPrint('⏱️ [Latency-Sound] 开始切换 Session 到 playback...');

      await waitForAllPlayers();
      debugPrint('⏱️ [Latency-Sound] waitForAllPlayers 结束，耗时: ${sw.elapsedMilliseconds}ms');

      await _configurePlaybackSession(retryCount: 0, totalSw: sw);
    });
  }

  /// 配置 playback 音频会话，带固定间隔重试以处理瞬时 InsufficientPriority 错误。
  static Future<void> _configurePlaybackSession({required int retryCount, required Stopwatch totalSw}) async {
    try {
      // 给原生层 (AppDelegate.stopMicrophone) 的 deactivate → setCategory → activate
      // 序列留出完成时间，避免与 audio_session 插件的 configure 产生竞态。
      if (retryCount > 0) {
        final delayMs = 50; // 固定 50ms 重试间隔，快速恢复瞬时 InsufficientPriority
        debugPrint('⏱️ [Latency-Sound] 重试 #$retryCount，等待 ${delayMs}ms...');
        await Future.delayed(Duration(milliseconds: delayMs));
      }

      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
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
      // AVAudioSessionErrorCodeInsufficientPriority (OSStatus 561017449) 是瞬时错误，
      // 通常在原生层音频会话尚未完全释放时出现。固定间隔重试最多 3 次。
      final errStr = e.toString();
      final isPriorityError = errStr.contains('561017449') ||
          errStr.contains('InsufficientPriority') ||
          errStr.contains('!pri');
      if (isPriorityError && retryCount < 3) {
        debugPrint('🔊 [SoundUtil] 切换 playback 遇到 InsufficientPriority，将重试 (${retryCount + 1}/3)');
        return _configurePlaybackSession(retryCount: retryCount + 1, totalSw: totalSw);
      }
      Global.logger.e('SoundUtil: 切换播放模式失败 (retryCount=$retryCount): $e');
      // 重试耗尽后必须重新抛出，让上层（transitTo/configureAudioSession）感知失败，
      // 否则 AudioEngine 会误以为切换成功，导致后续发音播放卡死（20s 超时）。
      rethrow;
    }
  }

  /// 切换为录音与播放并存模式
  static Future<void> usePlayAndRecordCategory() {
    return _sessionLock.protect(() async {
      if (PlatformUtils.isWeb) return;

      // 无论当前会话类别是否已经是 playAndRecord，只要发起切换/更新，都必须优先物理排空逻辑上已播完的 EarlyExit 播放器，
      // 确保发音尾音彻底自然淡出并物理释放硬件，根治单词发音与随后的 ASR 提示音/麦克风录音启动瞬间音频重采样或引擎并发冲突产生的爆音
      await _cleanupEarlyExitPlayers();

      if (_currentSessionCategory == 'playAndRecord') return;

      final sw = Stopwatch()..start();
      _logAudioState('会话切换前(→playAndRecord)');
      debugPrint('⏱️ [Latency-Sound] 开始执行 usePlayAndRecordCategory (ASR 准备)...');

      await waitForAllPlayers();
      debugPrint('⏱️ [Latency-Sound] waitForAllPlayers 结束，耗时: ${sw.elapsedMilliseconds}ms');

      await _configurePlayAndRecordSession(retryCount: 0, totalSw: sw);
    });
  }

  /// 配置 playAndRecord 音频会话，带固定间隔重试以处理瞬时 InsufficientPriority 错误。
  static Future<void> _configurePlayAndRecordSession({required int retryCount, required Stopwatch totalSw}) async {
    try {
      if (retryCount > 0) {
        final delayMs = 50; // 固定 50ms 重试间隔，快速恢复瞬时 InsufficientPriority
        debugPrint('⏱️ [Latency-Sound] 重试 #$retryCount (playAndRecord)，等待 ${delayMs}ms...');
        await Future.delayed(Duration(milliseconds: delayMs));
      }

      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.mixWithOthers |
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
        debugPrint('🔊 [SoundUtil] 切换 playAndRecord 遇到 InsufficientPriority，将重试 (${retryCount + 1}/3)');
        return _configurePlayAndRecordSession(retryCount: retryCount + 1, totalSw: totalSw);
      }
      Global.logger.e('SoundUtil: 切换为录放模式失败 (retryCount=$retryCount): $e');
      rethrow;
    }
  }

  /// 物理排空逻辑上已播完的 EarlyExit 播放器，确保发音尾音彻底释放硬件。
  /// 提取为独立方法，供 usePlaybackCategory 和 usePlayAndRecordCategory 共用，
  /// 避免 _logicallyFinishedPlayers 仅在录放切换时清理导致内存/引用泄漏。
  static Future<void> _cleanupEarlyExitPlayers() async {
    final earlyExitPlayers = _watchedPlayers.where((p) => _logicallyFinishedPlayers.contains(p)).toList();
    if (earlyExitPlayers.isEmpty) return;

    bool hasStoppedAny = false;
    final List<ja.AudioPlayer> successfullyCleaned = [];
    for (var p in earlyExitPlayers) {
      if (p.playing) {
        try {
          debugPrint('🔊 [AudioDiag] EarlyExit 强制stop: player=${p.hashCode}, pos=${p.position.inMilliseconds}ms');
          debugPrint('⏱️ [Latency-Sound] 强制 stop() 逻辑完成但物理仍活跃的播放器，彻底释放硬件资源...');
          await p.stop().timeout(const Duration(milliseconds: 100), onTimeout: () {});
          hasStoppedAny = true;
          successfullyCleaned.add(p);
        } catch (e) {
          debugPrint('🔊 [SoundUtil] 物理排空 stop() 播放器异常: $e');
        }
      } else {
        successfullyCleaned.add(p);
      }
    }
    _logicallyFinishedPlayers.removeAll(successfullyCleaned);
    
    // 如果确实执行了 stop 物理关停，给 Native 混音器 30ms 的物理排空与平滑过渡缓冲期，消除任何可能残留的硬件切音爆音
    if (hasStoppedAny) {
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }

  /// 预热核心高频音效，彻底消除首次分配 ExoPlayer 的延迟
  static Future<void> prewarmCoreSounds() async {
    if (PlatformUtils.isWeb || PlatformUtils.isTesting) return;
    for (int i = 0; i < _sfxPoolSize; i++) {
      if (_sfxPool.length <= i) {
        try {
          // 在连续创建 AudioPlayer 之间加入 50ms 延迟，给底层平台分配音频资源 and 通信时间，根治并发引起的冲突
          await Future.delayed(const Duration(milliseconds: 50));
          final player = createAudioPlayer();
          _sfxPool.add(player);
          watchPlayer(player);
          debugPrint('🔊 [SoundUtil] 音效池播放器 $i 初始化成功');
        } catch (e) {
          debugPrint('🔊 [SoundUtil] 音效池播放器 $i 初始化失败: $e');
        }
      }
    }
  }

  /// 获取音效池中当前可用的播放器实例（支持状态轮询与旧资源抢占）
  /// 使用互斥锁确保并发安全，防止两个音效抢同一播放器产生爆音。
  static Future<ja.AudioPlayer?> _getAvailableSfxPlayer() {
    return _sfxLock.protect(() async {
      if (!_audioSessionConfigured) {
        await configureAudioSession();
      }
      if (_sfxPool.length < _sfxPoolSize) {
        await prewarmCoreSounds();
      }
      if (_sfxPool.isEmpty) return null;
      
      final now = AppClock.now();
      ja.AudioPlayer? bestPlayer;
      
      // 1. 优先寻找未在播放，且 busy 状态已过期的播放器
      for (var player in _sfxPool) {
        final busyUntil = _playerBusyUntil[player];
        if (!player.playing && (busyUntil == null || now.isAfter(busyUntil))) {
          _logSfxAlloc('空闲优先', player);
          return player;
        }
      }

      // 2. 次优寻找 busy 状态已过期的播放器
      for (var player in _sfxPool) {
        final busyUntil = _playerBusyUntil[player];
        if (busyUntil == null || now.isAfter(busyUntil)) {
          _logSfxAlloc('busy过期', player);
          return player;
        }
      }
      
      // 3. 兜底策略：如果都在忙，选择最先开始忙（忙碌状态最久远）的那个播放器进行抢占/复用
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

  static void watchPlayer(ja.AudioPlayer player) {
    if (!_watchedPlayers.contains(player)) {
      _watchedPlayers.add(player);
    }
  }

  /// 从全局监视列表和逻辑完成列表中彻底移除指定的播放器，防止 dispose 后的残留超时
  static void unwatchPlayer(ja.AudioPlayer player) {
    _watchedPlayers.remove(player);
    _logicallyFinishedPlayers.remove(player);
    _playerBusyUntil.remove(player);
    _activeCutToken.remove(player);
    debugPrint('🔊 [SoundUtil] 已从监视名单安全移除播放器: ${player.hashCode}');
  }

  static Future<void> waitForAllPlayers() async {
    for (var player in _watchedPlayers) {
      // 优化：音效池播放器主要播放交互音效，无需在切换音频 Session 时强行等待它们播完，直接跳过，避免引入不必要的延时
      if (_sfxPool.contains(player)) {
        continue;
      }
      // EarlyExit 播放器：跳过流等待，改用 buffer delay 兜底（见 _cleanupEarlyExitPlayers）
      if (_logicallyFinishedPlayers.contains(player)) {
        continue;
      }
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
        } catch (e) {
          debugPrint('🔊 [SoundUtil] 等待播放器结束超时: $e');
        }
      }
    }
  }

  static ja.AudioPlayer get pronouncePlayer {
    if (_pronouncePlayer == null) {
      _pronouncePlayer = createAudioPlayer();
      watchPlayer(_pronouncePlayer!);
    }
    return _pronouncePlayer!;
  }

  static Future<void> playPronounceSound(WordVo word) async {
    var soundUrl = Util.getWordSoundUrl(word.spell, word: word);
    Global.logger.d('🔊 播放发音 [Spell: ${word.spell}, UpdateTime: ${word.updateTime}] URL: $soundUrl');
    await playSoundByUrl(soundUrl, pronouncePlayer, false);
  }

  static Future<void> playSoundByUrl(String soundUrl, ja.AudioPlayer player, bool disposeWhenFinish,
      {int loadTimeoutMs = 10000, int playTimeoutMs = 20000, double speed = 1.0, Future<void>? preWaitFuture}) async {
    final totalSw = Stopwatch()..start();
    try {
      if (!_audioSessionConfigured) await configureAudioSession();
      if (PlatformUtils.isWeb) await _ensureWebAudioUnlocked();

      // 架构设计优化 1：优先且必须确保 AVAudioSession 并行切换彻底完成，
      // 然后再对播放器执行 stop、挂载和播放核心操作，防止切换中硬件参数突变导致瞬间爆音或发音丢失。
      if (preWaitFuture != null) {
        final waitSw = Stopwatch()..start();
        await preWaitFuture;
        debugPrint('⏱️ [Latency-Sound] 等待并行 Session 切换完成，实耗: ${waitSw.elapsedMilliseconds}ms');
      }

      try {
        _logicallyFinishedPlayers.remove(player);
        // 软静音防护 (Soft-Mute Teardown)：如果前一个单词发音仍未播完就切词/打断，
        // 在 stop 前将音量拉到 0，消除 Native 音频流因半空拦腰截断（非零截断）产生的电流爆音
        if (player.playing) {
          await player.setVolume(0.0);
        }
        await player.stop();
      } catch (_) {}

      await player.setVolume(1.0);

      final loadSw = Stopwatch()..start();
      if (PlatformUtils.isWeb) {
        await player.setUrl(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
      } else {
        final cacheManager = DefaultCacheManager();
        FileInfo? fileInfo = await cacheManager.getFileFromCache(soundUrl);
        final String targetFilePath = fileInfo?.file.path ?? '';

        bool sourceChanged = true;

        // 架构设计优化 2：若播放器非 idle，且当前挂载的本地音频源与要播放的一致，
        // 彻底跳过极为昂贵的 setAudioSource，改用 0ms seek(zero) 重放，消除硬件流重建爆音。
        if (player.processingState != ja.ProcessingState.idle &&
            player.audioSource is ja.UriAudioSource) {
          final currentUri = (player.audioSource as ja.UriAudioSource).uri;
          if (currentUri.isScheme('file') &&
              targetFilePath.isNotEmpty &&
              currentUri.toFilePath() == targetFilePath) {
            sourceChanged = false;
          }
        }

        if (sourceChanged) {
          if (targetFilePath.isNotEmpty && await File(targetFilePath).exists()) {
            await player.setAudioSource(ja.AudioSource.uri(Uri.file(targetFilePath))).timeout(Duration(milliseconds: loadTimeoutMs));
          } else {
            var file = await cacheManager.getSingleFile(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
            await player.setAudioSource(ja.AudioSource.uri(Uri.file(file.path))).timeout(Duration(milliseconds: loadTimeoutMs));
          }
        } else {
          try {
            debugPrint('⚡ [SoundUtil] 检测到相同的音频源，跳过 setAudioSource，直接闪电 seek(zero) 重放');
            await player.seek(Duration.zero);
          } catch (e) {
            // 防御式兜底 Fallback：一旦物理/系统级 seek 异常，自动降级至正常的 setAudioSource 重新挂载，确保 100% 能发声
            debugPrint('⚠️ [SoundUtil] 闪电复用 seek 失败: $e，触发安全 fallback 重新挂载');
            if (targetFilePath.isNotEmpty && await File(targetFilePath).exists()) {
              await player.setAudioSource(ja.AudioSource.uri(Uri.file(targetFilePath))).timeout(Duration(milliseconds: loadTimeoutMs));
            } else {
              var file = await cacheManager.getSingleFile(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
              await player.setAudioSource(ja.AudioSource.uri(Uri.file(file.path))).timeout(Duration(milliseconds: loadTimeoutMs));
            }
          }
        }
      }
      debugPrint('⏱️ [Latency-Sound] 资源加载与对齐耗时: ${loadSw.elapsedMilliseconds}ms');

      await player.setSpeed(speed);
      
      final playCompletedFuture = player.playerStateStream
          .skip(1)
          .firstWhere((state) => 
              state.processingState == ja.ProcessingState.completed || 
              state.processingState == ja.ProcessingState.idle)
          .timeout(Duration(milliseconds: playTimeoutMs));
      
      final playSw = Stopwatch()..start();
      unawaited(player.play().catchError((_) {}));

      if (player.processingState != ja.ProcessingState.completed && 
          player.processingState != ja.ProcessingState.idle) {
        await playCompletedFuture;
      }

      _logicallyFinishedPlayers.add(player);
      debugPrint('⏱️ [Latency-Sound] 物理播放自然完成，耗时: ${playSw.elapsedMilliseconds}ms');
      Global.logger.d('🔊 [SoundUtil] playSoundByUrl 结束，总逻辑耗时: ${totalSw.elapsedMilliseconds}ms');
    } catch (e, st) {
      _logicallyFinishedPlayers.add(player);
      final errStr = e.toString();
      final isAbortError = errStr.contains('Connection aborted') || 
          errStr.contains('abort') || 
          errStr.contains('Loading interrupted');
      
      if (isAbortError) {
        Global.logger.i('🔊 [SoundUtil] 播放被中止/中断 (属于预期行为，安全忽略): $soundUrl');
      } else {
        Global.logger.e('播放异常: $soundUrl', error: e, stackTrace: st);
      }
    } finally {
      if (disposeWhenFinish) {
        Future.delayed(const Duration(seconds: 2), () {
          try {
            // 在 dispose 前，必须先无条件从全局监视名单中彻底移除，防止 disposed 后的 player 残留导致 waitForAllPlayers 访问崩溃
            unwatchPlayer(player);
            player.dispose().catchError((_) {});
          } catch (_) {}
        });
      }
    }
  }

  static Future<void> playAssetSound(
      String soundFileName, double speed, double volume, int timeoutInMilliSeconds, int sleepAfterPlayInMilliSeconds) async {
    try {
      final player = await _getAvailableSfxPlayer();
      if (player == null) return;
      
      _activeCutToken.remove(player); // 清除旧 cut token，防止误杀新声音

      final now = AppClock.now();
      final busyDuration = Duration(milliseconds: sleepAfterPlayInMilliSeconds > 0 ? sleepAfterPlayInMilliSeconds : 1000);
      _playerBusyUntil[player] = now.add(busyDuration);
      
      // 软静音防护 (Soft-Mute Teardown)：如果该播放器正处于活跃播放状态（例如被抢占或强行重放），
      // 在 stop 前将音量设为 0，防止由于音频流拦腰截断产生瞬时电压阶跃带来的爆音
      if (player.playing) {
        await player.setVolume(0.0);
      }
      await player.stop();
      await player.seek(Duration.zero);
      await player.setSpeed(speed);
      await player.setVolume(volume);
      await player.setAsset('assets/audio/$soundFileName').timeout(Duration(milliseconds: timeoutInMilliSeconds));
      unawaited(player.play().catchError((_) {}));
      
      if (sleepAfterPlayInMilliSeconds > 0) {
        await Future.delayed(Duration(milliseconds: sleepAfterPlayInMilliSeconds));
      }
    } catch (e) {
      debugPrint('🔊 playAssetSound 出错: $soundFileName, $e');
    }
  }

  static Future<void> playAsrReadyHintSound() async {
    debugPrint('🔊 [PERF] playAsrReadyHintSound START');
    await playAssetSound('asr_ready_hint.wav', 1.0, 0.2, 1000, 150);
    debugPrint('🔊 [PERF] playAsrReadyHintSound FINISHED');
  }

  /// 保温状态下，安全清理并重新播放 ASR 就绪提示音
  static Future<void> playAsrReadyHintSoundWithCleanup() async {
    await _cleanupEarlyExitPlayers();
    await playAsrReadyHintSound();
  }

  static Future<void> playAddSuccessSound() async {
    unawaited(playAssetSoundConcurrent('bubble-pop.wav', 1.0, 0.6));
  }

  static Future<void> playAssetSoundConcurrent(String soundFileName, double speed, double volume) async {
    await playAssetSound(soundFileName, speed, volume, 4000, 0);
  }

  static Future<void> playPronounceSound2(WordVo word, ja.AudioPlayer player, {Future<void>? preWaitFuture}) async {
    var soundUrl = Util.getWordSoundUrl(word.spell, word: word);
    await playSoundByUrl(soundUrl, player, false, preWaitFuture: preWaitFuture);
  }
  
  static Future<void> playSentenceSound2(String englishDigest, ja.AudioPlayer player, {double speed = 1.0, Future<void>? preWaitFuture}) async {
    var soundUrl = Util.getSentenceSoundUrl(englishDigest);
    await playSoundByUrl(soundUrl, player, false, speed: speed, preWaitFuture: preWaitFuture);
  }

  static Future<void> playPronounceSoundBySpell(String spell) async {
    await playSoundByUrl(Util.getWordSoundUrl(spell), createAudioPlayer(), true);
  }

  static Future<void> playPronounceSoundBySpell2(String spell, ja.AudioPlayer player, {double speed = 1.0}) async {
    await playSoundByUrl(Util.getWordSoundUrl(spell), player, false, speed: speed);
  }

  /// 预热 AudioPlayer：查找缓存并调用 setAudioSource 以触发底层平台播放器初始化。
  /// 不播放任何声音，仅用于消除首次 setAudioSource 的冷启动延迟（iOS AVQueuePlayer 初始化 ~2s）。
  /// 缓存未命中时不降级下载——下载是 playSoundByUrl 的职责。
  static Future<void> preloadAudioFromUrl(String soundUrl, ja.AudioPlayer player) async {
    if (PlatformUtils.isWeb) return;
    try {

      try {
        _logicallyFinishedPlayers.remove(player);
        // 软静音防护 (Soft-Mute Teardown)：如果前一个单词发音仍未播完就切词/预热，
        // 在 stop 前将音量拉到 0，消除 Native 音频流因半空瞬间切断产生的电流爆音
        if (player.playing) {
          await player.setVolume(0.0);
        }
        await player.stop();
      } catch (_) {}

      await player.setVolume(1.0);

      final cacheManager = DefaultCacheManager();
      final fileInfo = await cacheManager.getFileFromCache(soundUrl);
      if (fileInfo != null && await fileInfo.file.exists()) {
        await player.setAudioSource(
          ja.AudioSource.uri(Uri.file(fileInfo.file.path)),
        ).timeout(const Duration(milliseconds: 10000));
        debugPrint('⚡ [SoundUtil] AudioPlayer 预热完成: $soundUrl');
      }
    } catch (e) {
      debugPrint('⚡ [SoundUtil] AudioPlayer 预热失败 (非关键): $e');
    }
  }

  static void prefetchSounds(List<String> urls) {
    if (PlatformUtils.isWeb) return;
    for (var url in urls) {
      unawaited(() async {
        try {
          await DefaultCacheManager().downloadFile(url);
        } catch (_) {}
      }());
    }
  }

  static Future<void> playSentenceSound(String englishDigest) async {
    await playSoundByUrl(Util.getSentenceSoundUrl(englishDigest), createAudioPlayer(), true);
  }

  static Future<void> playAiStoryEnSound(String wordsHash) async {
    await playSoundByUrl(Util.getAiStoryEnSoundUrl(wordsHash), createAudioPlayer(), true, loadTimeoutMs: 10000, playTimeoutMs: 120000);
  }

  static Future<void> playAiStoryCnSound(String wordsHash) async {
    await playSoundByUrl(Util.getAiStoryCnSoundUrl(wordsHash), createAudioPlayer(), true, loadTimeoutMs: 10000, playTimeoutMs: 120000);
  }

  static Future<void> playAssetSoundCut(String soundFileName, double speed, double volume, Duration maxPlay) async {
    try {
      final player = await _getAvailableSfxPlayer();
      if (player == null) return;
      
      final now = AppClock.now();
      _playerBusyUntil[player] = now.add(maxPlay + const Duration(milliseconds: 100));
      
      // 软静音防护 (Soft-Mute Teardown)
      if (player.playing) {
        await player.setVolume(0.0);
      }
      await player.stop();
      await player.seek(Duration.zero);
      await player.setSpeed(speed);
      await player.setVolume(volume);
      await player.setAsset('assets/audio/$soundFileName');
      unawaited(player.play());
      
      // 使用 token 防止误杀：如果播放器在延迟期间被复用了，不 kill 新声音
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
      Global.logger.w('playAssetSoundCut 播放失败: $soundFileName, $e');
    }
  }

  static Future<void> _ensureWebAudioUnlocked() async {
    if (!PlatformUtils.isWeb || _webAudioUnlocked || _webUnlockInProgress) return;
    _webUnlockInProgress = true;
    try {
      final player = createAudioPlayer();
      await player.setVolume(0.0);
      await player.setAsset('assets/audio/thud.mp3');
      await player.play();
      await player.dispose();
      _webAudioUnlocked = true;
    } finally {
      _webUnlockInProgress = false;
    }
  }
}

class _Mutex {
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
    }).catchError((_) {}); // 避免前一个任务失败导致后一个任务无法执行
    return completer.future;
  }
}
