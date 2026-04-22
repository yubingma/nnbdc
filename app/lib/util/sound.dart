import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
// Avoid direct dart:io Platform on web; use PlatformUtils instead
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/utils.dart';

import '../api/vo.dart';

class SoundUtil {
  static AudioPlayer? _pronouncePlayer;
  static bool _webAudioUnlocked = false;
  static bool _webUnlockInProgress = false;
  static bool _audioSessionConfigured = false;
  static final Map<String, List<AudioPlayer>> _sfxPools = {};

  // 核心：引入忙碌锁定，记录每个播放器最后一次被指派的时间
  static final Map<AudioPlayer, DateTime> _playerBusyUntil = {};

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
      final player = AudioPlayer();
      if (PlatformUtils.isIOS) {
        await player.setAudioContext(AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.allowBluetooth,
              AVAudioSessionOptions.allowBluetoothA2DP,
            },
          ),
        ));
      } else if (PlatformUtils.isAndroid) {
        await player.setAudioContext(AudioContext(
          android: AudioContextAndroid(
            usageType: AndroidUsageType.media,
            contentType: AndroidContentType.speech,
            audioFocus: AndroidAudioFocus.none,
          ),
        ));
      }
      await player.dispose();
      _audioSessionConfigured = true;
      Global.logger.i('SoundUtil: 全局音频会话配置完成');

      _prewarmSfx(['thud.mp3', 'correct.mp3', 'fail.mp3', 'bubble-pop.mp3', 'asr_ready_hint.mp3']);
    } catch (e) {
      Global.logger.e('SoundUtil: 配置全局音频会话失败: $e');
    } finally {
      _configureFuture = null;
    }
  }

  static void _prewarmSfx(List<String> files) {
    for (var f in files) {
      _sfxPools.putIfAbsent(f, () {
        final p = AudioPlayer();
        p.setSource(AssetSource('audio/$f')).catchError((_) {});
        return [p];
      });
    }
  }

  /// 获取单词发音播放器实例
  static AudioPlayer get pronouncePlayer {
    _pronouncePlayer ??= AudioPlayer();
    return _pronouncePlayer!;
  }

  /// 播放单词发音
  static Future<void> playPronounceSound(WordVo word) async {
    var soundUrl = Util.getWordSoundUrl(word.spell, word: word);
    Global.logger.d('🔊 播放发音 [Spell: ${word.spell}, UpdateTime: ${word.updateTime}] URL: $soundUrl');
    await playSoundByUrl(soundUrl, pronouncePlayer, false);
  }

  /// 播放单词发音
  static Future<void> playPronounceSound2(WordVo word, AudioPlayer player) async {
    var soundUrl = Util.getWordSoundUrl(word.spell, word: word);
    Global.logger.d('🔊 播放发音 (指定播放器) [Spell: ${word.spell}, UpdateTime: ${word.updateTime}] URL: $soundUrl');
    await playSoundByUrl(soundUrl, player, false, loadTimeoutMs: 3000, playTimeoutMs: 5000);
  }

  /// 播放单词发音 (按拼写)
  static Future<void> playPronounceSoundBySpell(String spell) async {
    var soundUrl = Util.getWordSoundUrl(spell);
    await playSoundByUrl(soundUrl, AudioPlayer(), true);
  }

  /// 播放单词发音，使用已存在的AudioPlayer实例
  static Future<void> playPronounceSoundBySpell2(String spell, AudioPlayer player) async {
    var soundUrl = Util.getWordSoundUrl(spell);
    await playSoundByUrl(soundUrl, player, false, loadTimeoutMs: 3000, playTimeoutMs: 5000);
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
    await playSoundByUrl(soundUrl, AudioPlayer(), true);
  }

  /// 播放例句发音
  static Future<void> playSentenceSound2(String englishDigest, AudioPlayer player) async {
    var soundUrl = Util.getSentenceSoundUrl(englishDigest);
    await playSoundByUrl(soundUrl, player, false, loadTimeoutMs: 7000, playTimeoutMs: 20000);
  }

  /// 播放 ASR 就绪提示音
  static Future<void> playAsrReadyHintSound() async {
    // 使用并发播放模式，音量调低，不阻塞 ASR 启动
    unawaited(playAssetSoundConcurrent('asr_ready_hint.mp3', 1.0, 0.4));
  }

  /// 播放添加成功提示音
  static Future<void> playAddSuccessSound() async {
    unawaited(playAssetSoundConcurrent('bubble-pop.mp3', 1.0, 0.6));
  }

  static Future<void> playSoundByUrl(String soundUrl, AudioPlayer player, bool disposeWhenFinish,
      {int loadTimeoutMs = 3000, int playTimeoutMs = 10000}) async {
    StreamSubscription? subscription;
    try {
      if (!_audioSessionConfigured) {
        await configureAudioSession();
      }
      await player.setVolume(1.0);
      if (PlatformUtils.isWeb) {
        await _ensureWebAudioUnlocked();
      }

      if (!disposeWhenFinish) {
        try {
          final currentState = player.state;
          if (currentState == PlayerState.playing || currentState == PlayerState.paused) {
            await player.stop().timeout(const Duration(milliseconds: 500), onTimeout: () => {});
            // 移除了 100ms 的人工延迟，现代播放器通常不需要这个间隔
          }
        } catch (stopError, stackTrace) {
          ErrorHandler.handleError(stopError, stackTrace, logPrefix: '停止音频播放时出错', showToast: false);
        }
      }

      final completer = Completer<void>();
      subscription = player.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) {
          Global.logger.d('音频播放完成事件收到');
          completer.complete();
        }
      });

      // 额外监听状态变化，作为补丁，防止有些平台上 onPlayerComplete 不可靠
      StreamSubscription? stateSubscription;
      stateSubscription = player.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.completed || state == PlayerState.stopped) {
          if (!completer.isCompleted) {
            Global.logger.d('音频播放状态变化为完成/停止: $state');
            completer.complete();
          }
        }
      });

      try {
        if (PlatformUtils.isWeb) {
          await player.play(UrlSource(soundUrl)).timeout(Duration(milliseconds: loadTimeoutMs));
        } else {
          // 优先检查缓存，避免 getSingleFile 可能带来的网络检查/下载逻辑延迟
          final cacheManager = DefaultCacheManager();
          FileInfo? fileInfo = await cacheManager.getFileFromCache(soundUrl);
          
          String filePath;
          if (fileInfo != null) {
            filePath = fileInfo.file.path;
          } else {
            // 缓存未命中，则使用 getSingleFile 触发下载
            var file = await cacheManager.getSingleFile(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
            filePath = file.path;
          }
          
          // 移除了 50ms 的同步等待延迟，直接开始播放
          await player.play(DeviceFileSource(filePath)).timeout(Duration(milliseconds: loadTimeoutMs));
        }

        // 等待播放完成
        await completer.future.timeout(Duration(milliseconds: playTimeoutMs));

        // 播放完成后增加一小段静音缓冲时间，避免紧接着的音频切换导致的问题
        // 这里的 200ms 不影响播放开始的延迟，只影响 await 返回的时间
        await Future.delayed(const Duration(milliseconds: 100));
      } finally {
        await stateSubscription.cancel();
      }
    } on Exception catch (e, stackTrace) {
      ErrorHandler.handleAudioError(e, stackTrace, audioType: 'url:$soundUrl');
    } finally {
      await subscription?.cancel();
      if (disposeWhenFinish) {
        try {
          await player.dispose();
        } catch (e, stackTrace) {
          ErrorHandler.handleError(e, stackTrace, logPrefix: '释放音频播放器时出错', showToast: false);
        }
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
    final pool = _sfxPools.putIfAbsent(soundFileName, () => [AudioPlayer()]);
    final player = pool.first;
    
    try {
      await player.stop(); // 确保从头播放
      await player.setPlaybackRate(speed);
      await player.setVolume(volume);
      await player.play(AssetSource('audio/$soundFileName')).timeout(const Duration(milliseconds: 2000));
      
      // 等待播放完成
      await player.onPlayerComplete.first.timeout(Duration(milliseconds: timeoutInMilliSeconds));
      
      if (sleepAfterPlayInMilliSeconds > 0) {
        await Future.delayed(Duration(milliseconds: sleepAfterPlayInMilliSeconds));
      }
    } on TimeoutException catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放音效超时: $soundFileName', showToast: false);
    } catch (e, st) {
      ErrorHandler.handleError(e, st, logPrefix: '播放音效出错: $soundFileName', showToast: false);
    }
  }

  /// 并发播放音效
  static Future<void> playAssetSoundConcurrent(String soundFileName, double speed, double volume) async {
    if (!_audioSessionConfigured) {
      await configureAudioSession();
    }
    final pool = _sfxPools.putIfAbsent(soundFileName, () => [AudioPlayer()]);
    AudioPlayer? player;
    final now = AppClock.now();

    for (int i = 0; i < pool.length; i++) {
      final p = pool[i];
      final busyUntil = _playerBusyUntil[p] ?? DateTime(0);
      if (p.state != PlayerState.playing && now.isAfter(busyUntil)) {
        player = p;
        break;
      }
    }

    if (player == null && pool.length < _maxPlayersPerSfx) {
      player = AudioPlayer();
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
    AudioPlayer player,
    String soundFileName,
    double speed,
    double volume,
  ) async {
    try {
      if (player.state == PlayerState.playing) {
        await player.stop().timeout(const Duration(milliseconds: 1000), onTimeout: () {
          Global.logger.w('SoundUtil: stop() timeout for $soundFileName');
        });
      }
      await player.setPlaybackRate(speed);
      await player.setVolume(volume);

      final Completer<void> playCompleter = Completer<void>();

      player.onPlayerComplete.first.then((_) {
        if (!playCompleter.isCompleted) playCompleter.complete();
      });

      if (player.source == null) {
        await player.play(AssetSource('audio/$soundFileName')).timeout(const Duration(milliseconds: 3000), onTimeout: () {
          Global.logger.w('SoundUtil: play() timeout for $soundFileName');
        });
      } else {
        // 使用非常短的超时（如 150ms）去 await seek，防止引擎切分时死锁，
        // 同步又可以避免 seek 和 resume 在引擎底端并发导致音频采样丢包发颤。
        await player.seek(Duration.zero).timeout(const Duration(milliseconds: 150), onTimeout: () {
          Global.logger.d('SoundUtil: seek() timeout/skipped for $soundFileName');
        });
        await player.resume().timeout(const Duration(milliseconds: 3000), onTimeout: () {
          Global.logger.w('SoundUtil: resume() timeout for $soundFileName');
        });
      }

      if (PlatformUtils.isAndroid) {
        late StreamSubscription stateSubscription;
        stateSubscription = player.onPlayerStateChanged.listen((state) {
          if (state == PlayerState.completed || state == PlayerState.stopped) {
            if (!playCompleter.isCompleted) playCompleter.complete();
          }
        });
        await Future.any([
          playCompleter.future,
          Future.delayed(const Duration(milliseconds: 1500)),
        ]);
        await stateSubscription.cancel();
      } else {
        await Future.any([
          playCompleter.future,
          Future.delayed(const Duration(milliseconds: 1500)),
        ]);
      }
    } on Exception catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放后台音效出错: $soundFileName', showToast: false);
    }
  }

  /// 播放音效（限定最大奖励时长）
  static Future<void> playAssetSoundCut(String soundFileName, double speed, double volume, Duration maxPlay) async {
    if (!_audioSessionConfigured) {
      await configureAudioSession();
    }
    final pool = _sfxPools.putIfAbsent(soundFileName, () => [AudioPlayer()]);
    AudioPlayer? player;
    final now = AppClock.now();

    for (int i = 0; i < pool.length; i++) {
      final p = pool[i];
      final busyUntil = _playerBusyUntil[p] ?? DateTime(0);
      if (p.state != PlayerState.playing && now.isAfter(busyUntil)) {
        player = p;
        break;
      }
    }

    if (player == null && pool.length < _maxPlayersPerSfx) {
      player = AudioPlayer();
      pool.add(player);
    }

    player ??= pool[0];

    // 锁定
    _playerBusyUntil[player] = now.add(const Duration(milliseconds: 400));

    try {
      if (player.state == PlayerState.playing) {
        player.stop();
      }
      player.setPlaybackRate(speed);
      player.setVolume(volume);

      unawaited(player.play(AssetSource('audio/$soundFileName')));

      await Future.any([
        player.onPlayerComplete.first,
        Future.delayed(maxPlay),
      ]);

      if (player.state == PlayerState.playing) {
        player.stop();
      }
    } on Exception catch (e, stackTrace) {
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
      final AudioPlayer unlockPlayer = AudioPlayer();
      try {
        await unlockPlayer.setVolume(0.0);
      } catch (_) {
        // Ignore errors when setting volume for the dummy unlock player
      }
      try {
        unawaited(unlockPlayer.play(AssetSource('audio/thud.mp3')));
        unawaited(Future.delayed(const Duration(milliseconds: 500)).then((_) => unlockPlayer.dispose()));
      } finally {
        _webAudioUnlocked = true;
      }
    } finally {
      _webUnlockInProgress = false;
    }
  }
}
