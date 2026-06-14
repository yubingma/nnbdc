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
    _activeVolumeToken.clear();
    _playerLoadedAsset.clear();
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

  /// 判定音效池是否已经完全预热
  static bool get isSfxPoolFullyPrewarmed => _sfxPool.length >= _sfxPoolSize;
  static final Set<ja.AudioPlayer> _logicallyFinishedPlayers = {};
  static final Map<ja.AudioPlayer, DateTime> _playerBusyUntil = {};
  static final Map<ja.AudioPlayer, Object> _activeCutToken = {};
  static final Map<ja.AudioPlayer, Object> _activeVolumeToken = {};
  static final Map<ja.AudioPlayer, String> _playerLoadedAsset = {};
  
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
        // 即使状态一致，playback 模式仍需确保 native AVAudioSession 处于活跃。
        // iOS 会在两次播放之间 deactivate 会话，导致后续 setUrl 永远卡在
        // buffering 状态。但只有在底层 Category 确实不是 playback 时，才需要强制重配置，
        // 避免在连续播放时频繁重置硬件导致爆音。同时需确保等待所有活跃播放器停稳，
        // 防止未停稳时加载新音源导致的切音爆音。
        if (finalTargetMode == AudioMode.playback) {
          await waitForAllPlayers();
          final bool isCategoryChanged = _currentSessionCategory != 'playback';
          if (isCategoryChanged) {
            await usePlaybackCategory(force: true);
          }
          final delayMs = isCategoryChanged ? 150 : 80;
          await Future.delayed(Duration(milliseconds: delayMs));
        }
        return;
      }
 
      final sw = Stopwatch()..start();
      // 热切换仅在当前处于 record 模式时才有意义（保留麦克风保温）。
      // 当从 idle 切换到 playback 时必须走冷路径以调用 usePlaybackCategory() 激活音频会话。
      // 注意：_currentSessionCategory 可能已过时（如 idle 后仍为 'playAndRecord'），
      // 因此以 _activeMode 为准判断是否真的处于录音模式。
      final bool isActuallyRecording = _activeMode == AudioMode.record;
      final bool effectiveHotPlayback = hotPlayback && isActuallyRecording;
      debugPrint('🔊 [AudioEngine] 状态机开始转换: $_activeMode ➔ $finalTargetMode (hotPlayback: $hotPlayback, effective: $effectiveHotPlayback)');

      try {
        switch (finalTargetMode) {
          case AudioMode.playback:
            if (effectiveHotPlayback) {
              // a. 软件层热关停 ASR 识别输入流，保留麦克风物理流与 Audio Category 通道保温
              await asrInstance.stopAsr();
              // b. 强行平滑淡出（Soft-Mute）所有当前活跃的临时/音效播放器，彻底排空声卡缓冲区
              await _cleanupEarlyExitPlayers();
              // c. 原生 ASR 引擎停止后硬件稳定窗口，消除残余瞬态
              await Future.delayed(const Duration(milliseconds: 120));
            } else {
              // 判断是否因 Category 转换发生了硬件重构（在执行任何关麦/重配置前先判定）
              final bool isCategoryChanged = _currentSessionCategory != 'playback';

              // a. 物理关闭麦克风（冷关停）
              // 根治 InsufficientPriority (561017449) 错误：不论之前的 _activeMode 是什么，
              // 进入 playback 之前都必须确保原生麦克风彻底关闭并释放 ASR 占用，否则切换 Category 会锁死。
              await asrInstance.stopMicrophone();
              _currentSessionCategory = 'playback';
              // b. 强行平滑淡出（Soft-Mute）所有当前活跃 of 临时/音效播放器，彻底排空声卡缓冲区
              await _cleanupEarlyExitPlayers();
              
              // c. 物理配置 AudioSession 为高品质 playback 模式；若已是 playback 则跳过重配置以根除不必要会话切换导致的爆音
              await usePlaybackCategory(force: false);
              // d. Session 切换后硬件稳定窗口，消除 deactivate/reactivate 瞬态
              final delayMs = isCategoryChanged ? 150 : 80;
              await Future.delayed(Duration(milliseconds: delayMs));
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
            //    若是本已保温的热复用路径，提供 80ms 的平滑缓冲区释放与错峰时间，根除提示音与播放器冲突爆音。
            final delayMs = isColdStart ? 80 : 40;
            debugPrint('⏱️ [AudioEngine] 麦克风物理通道已激活 (${isColdStart ? "冷启动" : "热复用"})，错峰延迟 ${delayMs}ms 稳定时钟...');
            await Future.delayed(Duration(milliseconds: delayMs));
            // e. 稳定窗口结束后，正式播放“叮”的就绪提示音
            await playAsrReadyHintSound();
            break;
 
          case AudioMode.idle:
            await asrInstance.stopMicrophone();
            await _cleanupEarlyExitPlayers();
            // 进入 idle 后音频会话可能已被 ASR 关麦时 deactivated。
            // 只有当当前分类非 playback 时才重置为 none，若本身已是 playback，
            // 保持状态以避免重新配置，解决新批次首词因重新激活音频硬件造成的爆音。
            if (_currentSessionCategory != 'playback') {
              _currentSessionCategory = 'none';
            }
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
      // 判定是否属于自然放完（或物理已完成静默）的播放器：
      // 1. 已由 playCompletedFuture 登记在已播完列表 (_logicallyFinishedPlayers)
      // 2. 底层物理处理状态已经是 completed 或 idle
      final bool isLogicallyFinished = _logicallyFinishedPlayers.contains(p);
      final bool isPhysicallyCompleted = 
          p.processingState == ja.ProcessingState.completed ||
          p.processingState == ja.ProcessingState.idle;

      final bool shouldSkipStop = isLogicallyFinished || isPhysicallyCompleted;

      if (p.playing) {
        if (shouldSkipStop) {
          // 自然播放完毕的播放器，保持物理静默，跳过物理 stop() 截断，根除 Category 切换时的切音电流爆音
          debugPrint('🔊 [AudioDiag] Skip Physical Stop: player=${p.hashCode}, logicallyFinished=$isLogicallyFinished, physicallyCompleted=$isPhysicallyCompleted');
          successfullyCleaned.add(p);
        } else {
          try {
            debugPrint('🔊 [AudioDiag] EarlyExit 强制stop: player=${p.hashCode}');
            // 物理打断软静音防护 (Soft-Mute Teardown)：在强制 stop 前拉低音量，消除电平非零截断产生的电流爆音
            await p.setVolume(0.0);
            await p.stop().timeout(const Duration(milliseconds: 100), onTimeout: () {});
            hasStoppedAny = true;
            successfullyCleaned.add(p);
          } catch (e) {
            debugPrint('🔊 [SoundUtil] 物理排空 stop() 播放器异常: $e');
          }
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
    _activeVolumeToken.remove(player);
    _playerLoadedAsset.remove(player);
    debugPrint('🔊 [SoundUtil] 已从监视名单安全移除播放器: ${player.hashCode}');
  }

  static Future<void> waitForAllPlayers() async {
    // 使用 List.from 创建快照，防止异步等待期间 _watchedPlayers 被并发修改引发 Concurrent modification during iteration 异常
    final playersSnapshot = List<ja.AudioPlayer>.from(_watchedPlayers);
    for (var player in playersSnapshot) {
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
    if (PlatformUtils.isTesting) return;
    final totalSw = Stopwatch()..start();
    debugPrint(
      '🕵️ [AudioDiag] playSoundByUrl.enter | '
      'url=$soundUrl disposeWhenFinish=$disposeWhenFinish '
      'processingState=${player.processingState} playing=${player.playing} '
      'volume=${player.volume} speed=${player.speed}'
    );
    try {
      if (!_audioSessionConfigured) await configureAudioSession();
      if (PlatformUtils.isWeb) await _ensureWebAudioUnlocked();

      if (preWaitFuture != null) {
        final waitSw = Stopwatch()..start();
        await preWaitFuture;
        debugPrint('⏱️ [Latency-Sound] 等待并行 Session 切换完成，实耗: ${waitSw.elapsedMilliseconds}ms');
      }

      try {
        _logicallyFinishedPlayers.remove(player);
        // 复位播放器状态以确保能正确加载新音源。
        // - 如果正在播放中 → 静音 + stop（防爆音）
        // - 如果处于 buffering（前次 setUrl 仍在加载）→ stop 取消缓冲
        // - 其他状态 → pause + seek(0) 软复位，保持原生播放器存活
        final needHardStop = player.playing ||
            player.processingState == ja.ProcessingState.buffering ||
            player.processingState == ja.ProcessingState.loading;
        if (needHardStop) {
          await player.setVolume(0.0);
          await player.stop();
        } else {
          await player.pause();
        }
        await player.seek(Duration.zero);
      } catch (_) {}

      debugPrint(
        '🕵️ [AudioDiag] playSoundByUrl.afterReset | '
        'processingState=${player.processingState} playing=${player.playing}'
      );

      final loadSw = Stopwatch()..start();
      if (PlatformUtils.isWeb) {
        await player.setUrl(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
      } else {
        final cacheManager = DefaultCacheManager();

        /// 从本地缓存文件加载音频源。
        Future<bool> tryLoadFromCache(String filePath) async {
          try {
            await player.setAudioSource(ja.AudioSource.uri(Uri.file(filePath)))
                .timeout(Duration(milliseconds: loadTimeoutMs));
            if (player.processingState == ja.ProcessingState.ready ||
                player.processingState == ja.ProcessingState.loading) {
              return true;
            }
            debugPrint('🔍 [AudioDiag] setAudioSource 后 state=${player.processingState}，尝试 setUrl 兜底');
          } catch (e) {
            debugPrint('🔍 [AudioDiag] setAudioSource 异常: $e');
          }
          return false;
        }

        /// 从 HTTP URL 流式加载音频源（兜底方案）。
        Future<bool> tryLoadFromUrl(String url) async {
          try {
            await player.setUrl(url).timeout(Duration(milliseconds: loadTimeoutMs));
            // setUrl 对远程 URL 会进入 buffering（缓冲）状态，这是正常的加载中状态
            if (player.processingState == ja.ProcessingState.ready ||
                player.processingState == ja.ProcessingState.loading ||
                player.processingState == ja.ProcessingState.buffering) {
              return true;
            }
            debugPrint('🔍 [AudioDiag] setUrl 后 state=${player.processingState}');
          } catch (e) {
            debugPrint('🔍 [AudioDiag] setUrl 异常: $e');
          }
          return false;
        }

        FileInfo? fileInfo = await cacheManager.getFileFromCache(soundUrl);
        final String targetFilePath = fileInfo?.file.path ?? '';
        debugPrint('🔍 [AudioDiag] targetFilePath="$targetFilePath"');

        bool loaded = false;
        if (targetFilePath.isNotEmpty && await File(targetFilePath).exists()) {
          debugPrint('🔍 [AudioDiag] 尝试缓存文件: $targetFilePath');
          loaded = await tryLoadFromCache(targetFilePath);
        }
        if (!loaded) {
          debugPrint('🔍 [AudioDiag] 缓存加载失败，尝试 setUrl: $soundUrl');
          loaded = await tryLoadFromUrl(soundUrl);
        }
        if (!loaded) {
          debugPrint('🔍 [AudioDiag] 所有加载途径均失败');
          throw Exception('Failed to load audio source.');
        }
      }
      debugPrint('⏱️ [Latency-Sound] 资源加载与对齐耗时: ${loadSw.elapsedMilliseconds}ms');
      debugPrint(
        '🕵️ [AudioDiag] playSoundByUrl.afterSetAudioSource | '
        'processingState=${player.processingState} playing=${player.playing}'
      );

      await player.setSpeed(speed);

      final volumeToken = Object();
      _activeVolumeToken[player] = volumeToken;

      // 提前将音量升至淡入起始值，使 AVPlayer 启动时已处于非零音量，
      // 避免 play() 后 0→0.015 阶跃产生瞬态爆音。
      await player.setVolume(0.015);

      bool hasStartedPlaying = false;
      final playCompletedFuture = player.playerStateStream
          .firstWhere((state) {
            if (state.playing) {
              hasStartedPlaying = true;
            }
            final isFinished = state.processingState == ja.ProcessingState.completed ||
                state.processingState == ja.ProcessingState.idle;
            final isStoppedAfterStart = hasStartedPlaying && !state.playing;
            return isFinished || isStoppedAfterStart;
          })
          .timeout(Duration(milliseconds: playTimeoutMs));

      // 僵尸防护：当 playCompletedFuture 不在下面 await（因 player 已处于
      // completed/idle）时，其 timeout 异常会成为未处理 of zone 错误。
      // catchError 作为安全网，防止异常泄漏到 runZonedGuarded。
      // 回调必须返回 PlayerState 类型（Future 的类型参数），避免 runtime 断言。
      playCompletedFuture.catchError((_) => player.playerState);

      final playSw = Stopwatch()..start();
      unawaited(player.play().catchError((_) {}));
      debugPrint(
        '🕵️ [AudioDiag] playSoundByUrl.afterPlay | '
        'processingState=${player.processingState} playing=${player.playing}'
      );

      // 音量继续淡入（0.015 已在 play 前设置）
      unawaited(() async {
        try {
          await Future.delayed(const Duration(milliseconds: 6));
          if (_activeVolumeToken[player] != volumeToken) return;
          await player.setVolume(0.04);
          await Future.delayed(const Duration(milliseconds: 6));
          if (_activeVolumeToken[player] != volumeToken) return;
          await player.setVolume(0.08);
          await Future.delayed(const Duration(milliseconds: 6));
          if (_activeVolumeToken[player] != volumeToken) return;
          await player.setVolume(0.15);
          await Future.delayed(const Duration(milliseconds: 6));
          if (_activeVolumeToken[player] != volumeToken) return;
          await player.setVolume(0.25);
          await Future.delayed(const Duration(milliseconds: 6));
          if (_activeVolumeToken[player] != volumeToken) return;
          await player.setVolume(0.4);
          await Future.delayed(const Duration(milliseconds: 6));
          if (_activeVolumeToken[player] != volumeToken) return;
          await player.setVolume(0.55);
          await Future.delayed(const Duration(milliseconds: 6));
          if (_activeVolumeToken[player] != volumeToken) return;
          await player.setVolume(0.7);
          await Future.delayed(const Duration(milliseconds: 6));
          if (_activeVolumeToken[player] != volumeToken) return;
          await player.setVolume(0.85);
          await Future.delayed(const Duration(milliseconds: 6));
          if (_activeVolumeToken[player] != volumeToken) return;
          await player.setVolume(1.0);
        } catch (_) {}
      }());

      if (player.processingState != ja.ProcessingState.completed &&
          player.processingState != ja.ProcessingState.idle) {
        await playCompletedFuture;
      }

      _logicallyFinishedPlayers.add(player);
      debugPrint('⏱️ [Latency-Sound] 物理播放自然完成，耗时: ${playSw.elapsedMilliseconds}ms');
      debugPrint(
        '🕵️ [AudioDiag] playSoundByUrl.end | '
        'processingState=${player.processingState} playing=${player.playing} volume=${player.volume}'
      );
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
      
      final assetPath = 'assets/audio/$soundFileName';
      final bool isSameAsset = _playerLoadedAsset[player] == assetPath;
      if (!isSameAsset) {
        await player.setAsset(assetPath).timeout(Duration(milliseconds: timeoutInMilliSeconds));
        _playerLoadedAsset[player] = assetPath;
      }
      _logicallyFinishedPlayers.remove(player);

      bool hasStartedPlaying = false;
      final playCompletedFuture = player.playerStateStream
          .firstWhere((state) {
            if (state.playing) {
              hasStartedPlaying = true;
            }
            final isFinished = state.processingState == ja.ProcessingState.completed ||
                state.processingState == ja.ProcessingState.idle;
            final isStoppedAfterStart = hasStartedPlaying && !state.playing;
            return isFinished || isStoppedAfterStart;
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
      debugPrint('🔊 playAssetSound 出错: $soundFileName, $e');
    }
  }

  static Future<void> playAsrReadyHintSound() async {
    debugPrint('🔊 [PERF] playAsrReadyHintSound START');
    await playAssetSound('asr_ready_hint.wav', 1.0, 0.2, 1000, 100);
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
    if (PlatformUtils.isWeb || PlatformUtils.isTesting) return;
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
    if (PlatformUtils.isWeb || PlatformUtils.isTesting) return;
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
      
      final assetPath = 'assets/audio/$soundFileName';
      final bool isSameAsset = _playerLoadedAsset[player] == assetPath;
      if (!isSameAsset) {
        await player.setAsset(assetPath);
        _playerLoadedAsset[player] = assetPath;
      }
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
