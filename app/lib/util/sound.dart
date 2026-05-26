import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'pinyin.dart';

import 'package:flutter/foundation.dart';
import '../api/vo.dart';

class SoundUtil {
  static ja.AudioPlayer? _pronouncePlayer;
  static bool _webAudioUnlocked = false;
  static bool _webUnlockInProgress = false;
  static bool _audioSessionConfigured = false;
  static String currentSessionCategory = 'none';

  @visibleForTesting
  static set audioSessionConfigured(bool value) => _audioSessionConfigured = value;
  
  static final List<ja.AudioPlayer> _sfxPool = [];
  static const int _sfxPoolSize = 3;
  static final Set<ja.AudioPlayer> _logicallyFinishedPlayers = {};
  static final Map<ja.AudioPlayer, DateTime> _playerBusyUntil = {};
  
  /// 全局观察的播放器列表，用于在切换音频会话前确保它们都已播完
  static final List<ja.AudioPlayer> _watchedPlayers = [];

  static Future<void>? _configureFuture;

  /// 配置全局音频会话
  static Future<void> configureAudioSession() {
    if (_audioSessionConfigured) return Future.value();
    
    _configureFuture ??= _doConfigureAudioSession();
    return _configureFuture!;
  }

  static Future<void> _doConfigureAudioSession() async {
    try {
      await usePlaybackCategory();
      _audioSessionConfigured = true;
      Global.logger.i('SoundUtil: 全局音频会话配置完成');
      prewarmCoreSounds();
      prewarmPinyin();
    } catch (e) {
      Global.logger.e('SoundUtil: 配置全局音频会话失败: $e');
    } finally {
      _configureFuture = null;
    }
  }

  static final _sessionLock = _Mutex();

  /// 切换为高保真纯播放模式
  static Future<void> usePlaybackCategory({bool force = false}) {
    return _sessionLock.protect(() async {
      if (PlatformUtils.isWeb) return;
      if (currentSessionCategory == 'playback' && !force) return;
      
      final sw = Stopwatch()..start();
      debugPrint('⏱️ [Latency-Sound] 开始切换 Session 到 playback...');

      await waitForAllPlayers();
      debugPrint('⏱️ [Latency-Sound] waitForAllPlayers 结束，耗时: ${sw.elapsedMilliseconds}ms');

      try {
        final session = await AudioSession.instance;
        await session.configure(AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers, 
          avAudioSessionMode: AVAudioSessionMode.moviePlayback,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        )).timeout(const Duration(milliseconds: 1000));
        currentSessionCategory = 'playback';
        debugPrint('⏱️ [Latency-Sound] Session 切换到 playback 完成，耗时: ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        Global.logger.e('SoundUtil: 切换高保真播放模式失败: $e');
      }
    });
  }

  /// 切换为录音与播放并存模式
  static Future<void> usePlayAndRecordCategory() {
    return _sessionLock.protect(() async {
      if (PlatformUtils.isWeb) return;
      if (currentSessionCategory == 'playAndRecord') return;

      final sw = Stopwatch()..start();
      debugPrint('⏱️ [Latency-Sound] 开始执行 usePlayAndRecordCategory (ASR 准备)...');

      await waitForAllPlayers();
      debugPrint('⏱️ [Latency-Sound] waitForAllPlayers 结束，耗时: ${sw.elapsedMilliseconds}ms');

      // EarlyExit 播放器：事件驱动等 playing 变 false（音频硬件排空），最多等 200ms
      final earlyExitPlayers = _watchedPlayers.where((p) => _logicallyFinishedPlayers.contains(p)).toList();
      if (earlyExitPlayers.isNotEmpty) {
        final pending = earlyExitPlayers.where((p) => p.playing);
        if (pending.isNotEmpty) {
          await Future.wait(
            pending.map((p) => p.playingStream.firstWhere((playing) => !playing, orElse: () => false)),
          ).timeout(const Duration(milliseconds: 200), onTimeout: () => []);
        }
        _logicallyFinishedPlayers.removeAll(_watchedPlayers);
        debugPrint('⏱️ [Latency-Sound] EarlyExit buffer flush done');
      }

      try {
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
        currentSessionCategory = 'playAndRecord';
        debugPrint('⏱️ [Latency-Sound] Session 切换到 playAndRecord 完成，总耗时: ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        Global.logger.e('SoundUtil: 切换为录放模式失败: $e');
      }
    });
  }

  /// 预热核心高频音效，彻底消除首次分配 ExoPlayer 的延迟
  static Future<void> prewarmCoreSounds() async {
    if (PlatformUtils.isWeb || PlatformUtils.isTesting) return;
    for (int i = 0; i < _sfxPoolSize; i++) {
      if (_sfxPool.length <= i) {
        try {
          // 在连续创建 AudioPlayer 之间加入 50ms 延迟，给底层平台分配音频资源和通信时间，根治并发引起的冲突
          await Future.delayed(const Duration(milliseconds: 50));
          final player = ja.AudioPlayer();
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
  static Future<ja.AudioPlayer?> _getAvailableSfxPlayer() async {
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
        return player;
      }
    }
    
    // 2. 次优寻找 busy 状态已过期的播放器
    for (var player in _sfxPool) {
      final busyUntil = _playerBusyUntil[player];
      if (busyUntil == null || now.isAfter(busyUntil)) {
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
    
    return bestPlayer ?? _sfxPool[0];
  }

  static void watchPlayer(ja.AudioPlayer player) {
    if (!_watchedPlayers.contains(player)) {
      _watchedPlayers.add(player);
    }
  }

  static Future<void> waitForAllPlayers() async {
    for (var player in _watchedPlayers) {
      // EarlyExit 播放器：跳过流等待，改用 buffer delay 兜底（见 usePlayAndRecordCategory）
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
    _pronouncePlayer ??= ja.AudioPlayer();
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

      try {
        _logicallyFinishedPlayers.remove(player);
        await player.stop();
      } catch (_) {}

      await player.setVolume(1.0);

      final loadSw = Stopwatch()..start();
      if (PlatformUtils.isWeb) {
        await player.setUrl(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
      } else {
        final cacheManager = DefaultCacheManager();
        FileInfo? fileInfo = await cacheManager.getFileFromCache(soundUrl);
        if (fileInfo != null && await fileInfo.file.exists()) {
          await player.setAudioSource(ja.AudioSource.uri(Uri.file(fileInfo.file.path))).timeout(Duration(milliseconds: loadTimeoutMs));
        } else {
          var file = await cacheManager.getSingleFile(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
          await player.setAudioSource(ja.AudioSource.uri(Uri.file(file.path))).timeout(Duration(milliseconds: loadTimeoutMs));
        }
      }
      debugPrint('⏱️ [Latency-Sound] 资源加载耗时: ${loadSw.elapsedMilliseconds}ms');

      if (preWaitFuture != null) {
        final waitSw = Stopwatch()..start();
        await preWaitFuture;
        debugPrint('⏱️ [Latency-Sound] 等待并行 Session 切换完成，实耗: ${waitSw.elapsedMilliseconds}ms');
      }

      await player.setSpeed(speed);
      
      final playCompletedFuture = player.playerStateStream
          .skip(1)
          .firstWhere((state) => 
              state.processingState == ja.ProcessingState.completed || 
              state.processingState == ja.ProcessingState.idle)
          .timeout(Duration(milliseconds: playTimeoutMs));

      final positionExitFuture = Completer<void>();
      StreamSubscription? posSub;
      
      final playSw = Stopwatch()..start();
      unawaited(player.play().catchError((_) {}));
// 物理进度监听：如果进度接近时长，则提前完成
if (player.duration != null) {
  posSub = player.positionStream.listen((pos) {
    // 修正优化：提前 100ms 返回（从 250ms 缩减）。
    // 大多数 MP3 末尾有 50-100ms 的空白采样，这能确保听感完整且衔接极速。
    if (pos >= (player.duration! - const Duration(milliseconds: 100))) {
      if (!positionExitFuture.isCompleted) positionExitFuture.complete();
    }
  });
}

// 4. 三重保险：OS 事件 OR 物理进度监听
if (player.processingState != ja.ProcessingState.completed && 
    player.processingState != ja.ProcessingState.idle) {
  await Future.any([playCompletedFuture, positionExitFuture.future]);
}

await posSub?.cancel();
_logicallyFinishedPlayers.add(player);
debugPrint('⏱️ [Latency-Sound] 物理播放完成 (Balanced EarlyExit), 耗时: ${playSw.elapsedMilliseconds}ms');

// 注意：这里绝不能调用 player.stop()，否则会立即掐断 Native 层的剩余尾音。
// 我们让硬件自然播完最后 100ms，而 Dart 逻辑此时已经去启动 ASR 了。

Global.logger.d('🔊 [SoundUtil] playSoundByUrl 结束，总逻辑耗时: ${totalSw.elapsedMilliseconds}ms');
    } catch (e, st) {
      _logicallyFinishedPlayers.add(player);
      Global.logger.e('播放异常: $soundUrl', error: e, stackTrace: st);
    } finally {
      if (disposeWhenFinish) {
        Future.delayed(const Duration(seconds: 2), () {
          player.dispose().catchError((_) {});
        });
      }
    }
  }

  static Future<void> playAssetSound(
      String soundFileName, double speed, double volume, int timeoutInMilliSeconds, int sleepAfterPlayInMilliSeconds) async {
    try {
      final player = await _getAvailableSfxPlayer();
      if (player == null) return;
      
      final now = AppClock.now();
      final busyDuration = Duration(milliseconds: sleepAfterPlayInMilliSeconds > 0 ? sleepAfterPlayInMilliSeconds : 3500);
      _playerBusyUntil[player] = now.add(busyDuration);
      
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
    unawaited(playAssetSound('asr_ready_hint.wav', 1.0, 0.2, 1000, 150));
    debugPrint('🔊 [PERF] playAsrReadyHintSound DISPATCHED');
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
    await playSoundByUrl(Util.getWordSoundUrl(spell), ja.AudioPlayer(), true);
  }

  static Future<void> playPronounceSoundBySpell2(String spell, ja.AudioPlayer player, {double speed = 1.0}) async {
    await playSoundByUrl(Util.getWordSoundUrl(spell), player, false, speed: speed);
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
    await playSoundByUrl(Util.getSentenceSoundUrl(englishDigest), ja.AudioPlayer(), true);
  }

  static Future<void> playAiStoryEnSound(String wordsHash) async {
    await playSoundByUrl(Util.getAiStoryEnSoundUrl(wordsHash), ja.AudioPlayer(), true, loadTimeoutMs: 10000, playTimeoutMs: 120000);
  }

  static Future<void> playAiStoryCnSound(String wordsHash) async {
    await playSoundByUrl(Util.getAiStoryCnSoundUrl(wordsHash), ja.AudioPlayer(), true, loadTimeoutMs: 10000, playTimeoutMs: 120000);
  }

  static Future<void> playAssetSoundCut(String soundFileName, double speed, double volume, Duration maxPlay) async {
    try {
      final player = await _getAvailableSfxPlayer();
      if (player == null) return;
      
      final now = AppClock.now();
      _playerBusyUntil[player] = now.add(maxPlay + const Duration(milliseconds: 100));
      
      await player.stop();
      await player.seek(Duration.zero);
      await player.setSpeed(speed);
      await player.setVolume(volume);
      await player.setAsset('assets/audio/$soundFileName');
      unawaited(player.play());
      
      // 延迟 maxPlay 后自动停止播放以实现 cut 效果
      Future.delayed(maxPlay, () async {
        try {
          if (player.playing) {
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
      final player = ja.AudioPlayer();
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
