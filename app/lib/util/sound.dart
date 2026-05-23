import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
// Avoid direct dart:io Platform on web; use PlatformUtils instead
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'asr.dart';
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
  static final Map<String, List<ja.AudioPlayer>> _sfxPools = {};
  
  // 核心：引入忙碌锁定，记录每个播放器最后一次被指派的时间
  static final Map<ja.AudioPlayer, DateTime> _playerBusyUntil = {};

  static const int _maxPlayersPerSfx = 6; // 6路并发通道

  static Future<void>? _configureFuture;

  /// 配置全局音频会话
  static Future<void> configureAudioSession() {
    if (_audioSessionConfigured) return Future.value();
    
    _configureFuture ??= _doConfigureAudioSession();
    return _configureFuture!;
  }

  static Future<void> _doConfigureAudioSession() async {
    try {
      // 默认初始化为高保真播放模式 (playback)
      await usePlaybackCategory();
      
      _audioSessionConfigured = true;
      Global.logger.i('SoundUtil: 全局音频会话配置完成 (默认为高保真播放)');

      _prewarmSfx(['thud.mp3', 'correct.mp3', 'failed.mp3', 'bubble-pop.mp3', 'asr_ready_hint.mp3']);
      prewarmPinyin();
    } catch (e) {
      Global.logger.e('SoundUtil: 配置全局音频会话失败: $e');
    } finally {
      _configureFuture = null;
    }
  }

  static final _sessionLock = _Mutex();

  /// 切换为高保真纯播放模式 (无麦克风占用，无回声消除滤波，高动态范围，高保真度)
  static Future<void> usePlaybackCategory({bool force = false}) {
    return _sessionLock.protect(() async {
      if (PlatformUtils.isWeb) return;
      if (currentSessionCategory == 'playback' && !force) {
        return;
      }
      final sw = Stopwatch()..start();
      try {
        debugPrint('⏱️ [Latency-Sound] 开始切换 Session 到 playback...');
        final session = await AudioSession.instance;
        await session.configure(AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers |
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.allowAirPlay |
              AVAudioSessionCategoryOptions.allowBluetoothA2dp, 
          avAudioSessionMode: AVAudioSessionMode.moviePlayback, // 使用 moviePlayback 获得更丰满、不尖锐的音质
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music, // 改为 music 以获得更好的媒体音质
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
/// 全局观察的播放器列表，用于在切换音频会话前确保它们都已播完
static final List<ja.AudioPlayer> _watchedPlayers = [];

/// 逻辑上已认为播放结束的播放器集合，用于绕过底层硬件延迟
static final Set<ja.AudioPlayer> _logicallyFinishedPlayers = {};

/// 将一个播放器加入全局观察名单
static void watchPlayer(ja.AudioPlayer player) {
  if (!_watchedPlayers.contains(player)) {
    _watchedPlayers.add(player);
  }
}

/// 等待名单中所有播放器停止播放
static Future<void> waitForAllPlayers() async {
  for (var player in _watchedPlayers) {
    // 优化：增加逻辑结束判定。如果播放器在逻辑登记表中，说明它已经通过 EarlyExit 判定为结束，
    // 即使硬件层面的 player.playing 还没变 false (OS 延迟)，我们也立即准予接管。
    if (player.playing && 
        !_logicallyFinishedPlayers.contains(player) &&
        player.processingState != ja.ProcessingState.completed && 
        player.processingState != ja.ProcessingState.idle) {
      debugPrint('⏱️ [Latency-Sound] 检查到活跃播放器，进行物理级等待...');
      try {
        await player.playerStateStream.firstWhere((state) => 
            !state.playing || 
            state.processingState == ja.ProcessingState.completed || 
            state.processingState == ja.ProcessingState.idle)
        .timeout(const Duration(milliseconds: 1000));
      } catch (e) {
        debugPrint('🔊 [SoundUtil] 等待播放器结束超时: $e');
      }
    }
  }
  // 彻底移除延迟，实现零损耗衔接
}/// 切换为录音与播放并存模式 (用于 ASR 语音识别场景，匹配 iOS 原生配置，优化蓝牙高保真度)
static Future<void> usePlayAndRecordCategory() {
  return _sessionLock.protect(() async {
    if (PlatformUtils.isWeb) return;
    if (currentSessionCategory == 'playAndRecord') {
      Global.logger.d('🔊 [SoundUtil] 当前音频分类已是 playAndRecord，无须重复配置');
      debugPrint('🔊 [SoundUtil] 当前音频分类已是 playAndRecord，无须重复配置');
      return;
    }

    // 在配置全局 AudioSession 切换之前，优雅等待所有观察中的播放器播完，防止尾音截断
    await waitForAllPlayers();

    // 原有的 pronouncePlayer 独立判断保留作为双重保险
    if (_pronouncePlayer != null && _pronouncePlayer!.playing) {
        final p = _pronouncePlayer!;
        Global.logger.i('🔊 [SoundUtil] 检测到 pronouncePlayer 正在播放，等待其播放完毕再切换音频会话类型...');
        try {
          await p.playerStateStream
              .firstWhere((state) => 
                  !state.playing || 
                  state.processingState == ja.ProcessingState.completed || 
                  state.processingState == ja.ProcessingState.idle)
              .timeout(const Duration(milliseconds: 2500));
          await Future.delayed(const Duration(milliseconds: 100)); // 额外延迟 100ms 保证硬件缓冲区完全播放完
          Global.logger.i('🔊 [SoundUtil] pronouncePlayer 播放完毕，开始切换音频会话...');
        } catch (e) {
          Global.logger.w('🔊 [SoundUtil] 等待 pronouncePlayer 播放完毕超时或异常: $e');
        }
      }

      try {
        final session = await AudioSession.instance;
        await session.configure(AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
              AVAudioSessionCategoryOptions.mixWithOthers |
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.allowAirPlay |
              AVAudioSessionCategoryOptions.allowBluetoothA2dp, // 支持蓝牙高保真立体声
          avAudioSessionMode: AVAudioSessionMode.defaultMode, // 改用 defaultMode 获得平坦频响和最自然的提示音音质（避免 videoRecording 在某些 iOS 设备上触发的尖锐高频均衡滤波）
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        )).timeout(const Duration(milliseconds: 1000));
        // Preferred sample rate setting removed (unsupported in audio_session)
        currentSessionCategory = 'playAndRecord';
        Global.logger.i('🔊 [SoundUtil] 成功切换音频会话为: playAndRecord (录音与播放并存，启用 A2DP 蓝牙高保真)');
        debugPrint('🔊 [SoundUtil] 成功切换音频会话为: playAndRecord (录音与播放并存，启用 A2DP 蓝牙高保真)');
      } catch (e) {
        Global.logger.e('SoundUtil: 切换为录放模式失败: $e');
      }
    });
  }

  static void _prewarmSfx(List<String> files) {
    if (PlatformUtils.isWeb) return;
    
    // 使用异步队列串行预热音效，避免瞬间并发引发 Android MediaCodec OMX 解码器过载与加载打断错误
    unawaited(() async {
      for (var f in files) {
        // 加载间隔 150ms，给底层音频框架和硬件解码器的分配与初始化提供充足的时间
        await Future.delayed(const Duration(milliseconds: 150));
        
        ja.AudioPlayer? p;
        runZonedGuarded(() async {
          p = ja.AudioPlayer();
          try {
            // 加载资产，设置 3 秒超时限制，避免老旧设备长时间挂起
            await p!.setAsset('assets/audio/$f').timeout(const Duration(seconds: 3));
            
            // 只有成功加载的播放器才放入 SFX 池中
            _sfxPools.putIfAbsent(f, () => []);
            if (!_sfxPools[f]!.contains(p!)) {
              _sfxPools[f]!.add(p!);
            }
          } catch (e) {
            final errorStr = e.toString();
            if (errorStr.contains('Connection aborted') || errorStr.contains('abort') || errorStr.contains('Loading interrupted')) {
              Global.logger.i('🔊 [SoundUtil] 预热音效被中止/中断 (属于预期行为): $f');
            } else {
              Global.logger.w('🔊 [SoundUtil] 预热音效失败 assets/audio/$f: $e，已安全释放该播放器');
            }
            try {
              await p?.dispose();
            } catch (_) {}
          }
        }, (error, stack) {
          final errorStr = error.toString();
          if (errorStr.contains('Connection aborted') || errorStr.contains('abort') || errorStr.contains('Loading interrupted')) {
            Global.logger.i('🔊 [SoundUtil] 预热音效 Zone 拦截中止/中断 (属于预期行为): $f');
          } else {
            Global.logger.w('🔊 [SoundUtil] 预热音效异步 Zone 拦截异常 assets/audio/$f: $error');
          }
          try {
            p?.dispose();
          } catch (_) {}
        });
      }
    }());
  }


  /// 获取单词发音播放器实例
  static ja.AudioPlayer get pronouncePlayer {
    _pronouncePlayer ??= ja.AudioPlayer();
    return _pronouncePlayer!;
  }

  /// 播放单词发音
  static Future<void> playPronounceSound(WordVo word) async {
    var soundUrl = Util.getWordSoundUrl(word.spell, word: word);
    Global.logger.d('🔊 播放发音 [Spell: ${word.spell}, UpdateTime: ${word.updateTime}] URL: $soundUrl');
    await playSoundByUrl(soundUrl, pronouncePlayer, false);
  }

  /// 播放单词发音
  static Future<void> playPronounceSound2(WordVo word, ja.AudioPlayer player, {Future<void>? preWaitFuture}) async {
    var soundUrl = Util.getWordSoundUrl(word.spell, word: word);
    Global.logger.d('🔊 播放发音 (指定播放器) [Spell: ${word.spell}, UpdateTime: ${word.updateTime}] URL: $soundUrl');
    await playSoundByUrl(soundUrl, player, false, preWaitFuture: preWaitFuture);
  }

  /// 播放单词发音 (按拼写)
  static Future<void> playPronounceSoundBySpell(String spell) async {
    var soundUrl = Util.getWordSoundUrl(spell);
    await playSoundByUrl(soundUrl, ja.AudioPlayer(), true);
  }

  /// 播放单词发音，使用已存在的播放器实例
  static Future<void> playPronounceSoundBySpell2(String spell, ja.AudioPlayer player, {double speed = 1.0}) async {
    var soundUrl = Util.getWordSoundUrl(spell);
    await playSoundByUrl(soundUrl, player, false, speed: speed);
  }

  /// 预取多个发音文件到缓存
  static void prefetchSounds(List<String> urls) {
    if (PlatformUtils.isWeb) return;
    for (var url in urls) {
      // 使用 unawaited 结合 try-catch 异步块，避免 catchError 的返回值类型问题
      unawaited(() async {
        try {
          // 这里的 downloadFile 会检查缓存，如果已存在则不会重复下载
          await DefaultCacheManager().downloadFile(url);
        } catch (e) {
          Global.logger.w('SoundUtil: 预取音频失败: $url, $e');
        }
      }());
    }
  }

  /// 播放例句发音
  static Future<void> playSentenceSound(String englishDigest) async {
    var soundUrl = Util.getSentenceSoundUrl(englishDigest);
    await playSoundByUrl(soundUrl, ja.AudioPlayer(), true);
  }

  /// 播放 AI 短文发音 (英文)
  static Future<void> playAiStoryEnSound(String wordsHash) async {
    var soundUrl = Util.getAiStoryEnSoundUrl(wordsHash);
    await playSoundByUrl(soundUrl, ja.AudioPlayer(), true, loadTimeoutMs: 10000, playTimeoutMs: 120000);
  }

  /// 播放 AI 短文发音 (中文)
  static Future<void> playAiStoryCnSound(String wordsHash) async {
    var soundUrl = Util.getAiStoryCnSoundUrl(wordsHash);
    await playSoundByUrl(soundUrl, ja.AudioPlayer(), true, loadTimeoutMs: 10000, playTimeoutMs: 120000);
  }

  /// 播放例句发音
  static Future<void> playSentenceSound2(String englishDigest, ja.AudioPlayer player, {double speed = 1.0, Future<void>? preWaitFuture}) async {
    var soundUrl = Util.getSentenceSoundUrl(englishDigest);
    await playSoundByUrl(soundUrl, player, false, speed: speed, preWaitFuture: preWaitFuture);
  }

  /// 播放 ASR 就绪提示音
  static Future<void> playAsrReadyHintSound() async {
    if (PlatformUtils.isIOS) {
      Global.logger.i("🔊 [SoundUtil] iOS 平台绕过 playAsrReadyHintSound (改为原生播放)");
      return;
    }
    // 使用并发播放模式，音量调低，不阻塞 ASR 启动。
    // 将速度提升至 2.5 倍，使其变得极其短促（类似清脆的“滴”），缩短时间至 ~150ms 左右
    unawaited(playAssetSoundConcurrent('asr_ready_hint.mp3', 2.5, 0.2));
  }

  /// 播放添加成功提示音
  static Future<void> playAddSuccessSound() async {
    unawaited(playAssetSoundConcurrent('bubble-pop.mp3', 1.0, 0.6));
  }

  static Future<void> playSoundByUrl(String soundUrl, ja.AudioPlayer player, bool disposeWhenFinish,
      {int loadTimeoutMs = 10000, int playTimeoutMs = 20000, double speed = 1.0, Future<void>? preWaitFuture}) async {
    final totalSw = Stopwatch()..start();
    try {
      if (!_audioSessionConfigured) {
        await configureAudioSession();
      }
      if (PlatformUtils.isWeb) {
        await _ensureWebAudioUnlocked();
      }

      // 1. 先停止当前播放器，彻底清空并重置其内部状态，释放硬件资源，并确保 BehaviorSubject 状态干净
      try {
        _logicallyFinishedPlayers.remove(player); // 开启新任务，清除之前的逻辑结束标志
        await player.stop();
      } catch (e) {
        debugPrint('🔊 [SoundUtil] 停止播放器时出现非致命错误: $e');
      }

      // 显式确保音量最大
      await player.setVolume(1.0);

      final loadSw = Stopwatch()..start();
      // 设置源
      if (PlatformUtils.isWeb) {
        await player.setUrl(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
      } else {
        final cacheManager = DefaultCacheManager();
        FileInfo? fileInfo = await cacheManager.getFileFromCache(soundUrl);
        if (fileInfo != null) {
          final file = fileInfo.file;
          if (await file.exists()) {
            final size = await file.length();
            if (size < 2048) {
              Global.logger.w('⚠️ [SoundUtil] 警告：音频文件大小过小 (${size} 字节): $soundUrl');
            }
            await player.setAudioSource(ja.AudioSource.uri(Uri.file(file.path))).timeout(Duration(milliseconds: loadTimeoutMs));
          } else {
            var file = await cacheManager.getSingleFile(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
            await player.setAudioSource(ja.AudioSource.uri(Uri.file(file.path))).timeout(Duration(milliseconds: loadTimeoutMs));
          }
        } else {
          var file = await cacheManager.getSingleFile(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
          await player.setAudioSource(ja.AudioSource.uri(Uri.file(file.path))).timeout(Duration(milliseconds: loadTimeoutMs));
        }
      }
      debugPrint('⏱️ [Latency-Sound] 资源加载耗时: ${loadSw.elapsedMilliseconds}ms');

      // 关键：在真正 play 前，等待外部并行进行的 ASR 停止和 Session 切换
      if (preWaitFuture != null) {
        final waitSw = Stopwatch()..start();
        await preWaitFuture;
        debugPrint('⏱️ [Latency-Sound] 等待并行 Session 切换完成，实耗: ${waitSw.elapsedMilliseconds}ms');
      }

      // 设置倍速
      await player.setSpeed(speed);
      
      // 2. 预先建立双重保险状态等待 Future
      final playCompletedFuture = player.playerStateStream
          .skip(1)
          .firstWhere((state) => 
              state.processingState == ja.ProcessingState.completed || 
              state.processingState == ja.ProcessingState.idle)
          .timeout(Duration(milliseconds: playTimeoutMs));

      // 极致优化：建立 Position 监听 Future，实现真正的物理播完即返回
      final positionExitFuture = Completer<void>();
      StreamSubscription? posSub;
      
      final playSw = Stopwatch()..start();
      // 3. 执行播放
      await player.play();

      // 物理进度监听：如果进度接近时长，则提前完成
      if (player.duration != null) {
        posSub = player.positionStream.listen((pos) {
          // 激进优化：提前 150ms 返回，这对短音频的体感提升巨大
          if (pos >= (player.duration! - const Duration(milliseconds: 150))) {
            if (!positionExitFuture.isCompleted) positionExitFuture.complete();
          }
        });
      }

      // 4. 三重保险：OS 事件 OR 物理进度监听
      if (player.processingState != ja.ProcessingState.completed && 
          player.processingState != ja.ProcessingState.idle) {
        await Future.any([
          playCompletedFuture,
          positionExitFuture.future,
        ]);
      }
      
      await posSub?.cancel();
      _logicallyFinishedPlayers.add(player); // 关键：登记逻辑结束标志，瞬间释放 ASR 等待锁
      debugPrint('⏱️ [Latency-Sound] 物理播放真正完成 (Aggressive EarlyExit), 耗时: ${playSw.elapsedMilliseconds}ms');

      // 关键优化：播放完成后立即【异步】显式停止，强制 snap 状态到 idle
      // 停止操作绝对不能 await，在某些 Android 设备上它会耗时 ~500ms 阻塞主线程
      unawaited(player.stop().catchError((e) => debugPrint('🔊 [SoundUtil] 后台异步停止失败: $e')));

      Global.logger.d('🔊 [SoundUtil] playSoundByUrl 结束，总逻辑耗时: ${totalSw.elapsedMilliseconds}ms');
    } catch (e, stackTrace) {
      final errorStr = e.toString();
      Global.logger.e('🔊 [SoundUtil] playSoundByUrl 捕获异常: $e', error: e, stackTrace: stackTrace);
      debugPrint('🔊 [SoundUtil] playSoundByUrl 捕获异常: $e');

      if (errorStr.contains('Connection aborted') || errorStr.contains('abort')) {
        Global.logger.i('🔊 [SoundUtil] 播放被中止: $soundUrl');
        return;
      }
      if (e is Exception) {
        ErrorHandler.handleAudioError(e, stackTrace, audioType: 'ja_url:$soundUrl');
      }
    } finally {
      if (disposeWhenFinish) {
        // 极致优化：异步销毁，不阻塞当前音频流向 ASR 的衔接流程
        unawaited(() async {
          try {
            debugPrint('🔊 [SoundUtil] 正在后台异步释放播放器资源...');
            await player.dispose();
          } catch (e) {
            debugPrint('🔊 [SoundUtil] 异步释放播放器失败: $e');
          }
        }());
      }
    }
  }

  /// 播放资产音效（使用池化播放器以提升性能）
  static Future<void> playAssetSound(
      String soundFileName, double speed, double volume, int timeoutInMilliSeconds, int sleepAfterPlayInMilliSeconds) async {
    if (!_audioSessionConfigured) {
      await configureAudioSession();
    }
    
    // 获取或创建该音效对应的播放器（单例模式，避免重复创建）
    final pool = _sfxPools.putIfAbsent(soundFileName, () => [ja.AudioPlayer()]);
    final player = pool.first;
    
    final startTime = DateTime.now().millisecondsSinceEpoch;
    Global.logger.i("🔊 [SoundUtil] 触发播放音效时的实际音频会话分类为: $currentSessionCategory | 音效名: $soundFileName");
    debugPrint("🔊 [SoundUtil] 触发播放音效时的实际音频会话分类为: $currentSessionCategory | 音效名: $soundFileName");
    try {
      await player.stop(); // 确保停止
      await player.seek(Duration.zero);
      await player.setSpeed(speed);
      await player.setVolume(volume);
      
      // 预热或重新设置 asset
      await player.setAsset('assets/audio/$soundFileName').timeout(Duration(milliseconds: timeoutInMilliSeconds));
      
      await player.play().timeout(Duration(milliseconds: timeoutInMilliSeconds));
      
      if (sleepAfterPlayInMilliSeconds > 0) {
        await Future.delayed(Duration(milliseconds: sleepAfterPlayInMilliSeconds));
      }
      Global.logger.d("~~~~~音效播放完成: $soundFileName (耗时: ${DateTime.now().millisecondsSinceEpoch - startTime}ms)");
    } on TimeoutException catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放音效超时: $soundFileName', showToast: false);
    } catch (e, st) {
      final errorStr = e.toString();
      if (errorStr.contains('Connection aborted') || errorStr.contains('abort') || errorStr.contains('Loading interrupted')) {
        Global.logger.i('🔊 [SoundUtil] 音效播放被中止/中断 (属于预期行为): $soundFileName');
        return;
      }
      ErrorHandler.handleError(e, st, logPrefix: '播放音效出错: $soundFileName', showToast: false);
    }
  }

  /// 并发播放音效
  static Future<void> playAssetSoundConcurrent(String soundFileName, double speed, double volume) async {
    await configureAudioSession();
    // Ensure we are in high‑fidelity playback mode for short UI feedback sounds,
    // but DO NOT switch if we are currently using playAndRecord (e.g. during ASR active)
    // to prevent tearing down the iOS microphone stream/audio engine.
    // 如果 ASR 当前并非活跃启动状态，则我们可以安全、坚决地切回高保真播放分类以获得悦耳的音质。
    final asrState = Asr().state;
    if (currentSessionCategory != 'playAndRecord' || (asrState != AsrState.started && asrState != AsrState.stopping)) {
      await usePlaybackCategory();
    }
    if (PlatformUtils.isWeb) return;
    Global.logger.i("🔊 [SoundUtil] 触发并发播放音效时的实际音频会话分类为: $currentSessionCategory | 音效名: $soundFileName");
    debugPrint("🔊 [SoundUtil] 触发并发播放音效时的实际音频会话分类为: $currentSessionCategory | 音效名: $soundFileName");

    final pool = _sfxPools.putIfAbsent(soundFileName, () => []);
    ja.AudioPlayer? player;
    final now = AppClock.now();

    for (int i = 0; i < pool.length; i++) {
      final p = pool[i];
      final busyUntil = _playerBusyUntil[p] ?? DateTime(0);
      // ja.AudioPlayer 不容易直接判断是否在 play，这里主要靠 busyUntil 逻辑
      if (now.isAfter(busyUntil)) {
        player = p;
        break;
      }
    }

    if (player == null && pool.length < _maxPlayersPerSfx) {
      player = ja.AudioPlayer();
      pool.add(player);
    }

    player ??= pool[0];

    // 锁定该播放器
    _playerBusyUntil[player] = now.add(const Duration(milliseconds: 300));

    return _playAssetSoundInBackground(player, soundFileName, speed, volume).catchError((error, stackTrace) {
      ErrorHandler.handleError(error, stackTrace, logPrefix: '并发播放音效出错: $soundFileName', showToast: false);
    });
  }

  static Future<void> _playAssetSoundInBackground(
    ja.AudioPlayer player,
    String soundFileName,
    double speed,
    double volume,
  ) async {
    try {
      await player.stop();
      await player.seek(Duration.zero);
      await player.setSpeed(speed);
      await player.setVolume(volume);

      await player.setAsset('assets/audio/$soundFileName');
      await player.play().timeout(const Duration(milliseconds: 3000));
      // Wait for completion or idle state
      await player.playerStateStream.firstWhere((state) =>
          state.processingState == ja.ProcessingState.completed ||
          state.processingState == ja.ProcessingState.idle);
    } catch (e, stackTrace) {
      final errorStr = e.toString();
      if (errorStr.contains('Connection aborted') || errorStr.contains('abort') || errorStr.contains('Loading interrupted')) {
        Global.logger.i('🔊 [SoundUtil] 音效播放被中止/中断 (属于预期行为): $soundFileName');
        return;
      }
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放音效出错: $soundFileName', showToast: false);
    } finally {
      try {
        await player.stop();
      } catch (_) {}
    }
  }

  /// 播放音效（限定最大奖励时长）
  static Future<void> playAssetSoundCut(String soundFileName, double speed, double volume, Duration maxPlay) async {
    if (!_audioSessionConfigured) {
      await configureAudioSession();
    }
    Global.logger.i("🔊 [SoundUtil] 触发被裁剪音效时的实际音频会话分类为: $currentSessionCategory | 音效名: $soundFileName");
    debugPrint("🔊 [SoundUtil] 触发被裁剪音效时的实际音频会话分类为: $currentSessionCategory | 音效名: $soundFileName");
    final pool = _sfxPools.putIfAbsent(soundFileName, () => [ja.AudioPlayer()]);
    ja.AudioPlayer? player;
    final now = AppClock.now();

    for (int i = 0; i < pool.length; i++) {
      final p = pool[i];
      final busyUntil = _playerBusyUntil[p] ?? DateTime(0);
      if (now.isAfter(busyUntil)) {
        player = p;
        break;
      }
    }

    if (player == null && pool.length < _maxPlayersPerSfx) {
      player = ja.AudioPlayer();
      pool.add(player);
    }

    player ??= pool[0];

    // 锁定
    _playerBusyUntil[player] = now.add(const Duration(milliseconds: 400));

    try {
      await player.stop();
      await player.seek(Duration.zero);
      await player.setSpeed(speed);
      await player.setVolume(volume);

      await player.setAsset('assets/audio/$soundFileName');
      
      unawaited(player.play());

      await Future.delayed(maxPlay);

      if (player.playing) {
        await player.stop();
      }
    } on Exception catch (e, stackTrace) {
      final errorStr = e.toString();
      if (errorStr.contains('Connection aborted') || errorStr.contains('abort') || errorStr.contains('Loading interrupted')) {
        Global.logger.i('🔊 [SoundUtil] 音效播放被中止/中断 (属于预期行为): $soundFileName');
        return;
      }
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放音效出错: $soundFileName', showToast: false);
    }
  }

  /// 确保 Web 平台已通过用户手势解锁音频播放
  static Future<void> _ensureWebAudioUnlocked() async {
    if (!PlatformUtils.isWeb) return;
    if (_webAudioUnlocked) return;
    if (_webUnlockInProgress) return;
    _webUnlockInProgress = true;
    try {
      final ja.AudioPlayer unlockPlayer = ja.AudioPlayer();
      try {
        await unlockPlayer.setVolume(0.0);
        await unlockPlayer.setAsset('assets/audio/thud.mp3');
        await unlockPlayer.play();
      } catch (_) {
        // Ignore errors when setting volume for the dummy unlock player
      } finally {
        await unlockPlayer.dispose();
        _webAudioUnlocked = true;
      }
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
