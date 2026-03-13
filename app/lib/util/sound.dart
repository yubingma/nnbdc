import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
// Avoid direct dart:io Platform on web; use PlatformUtils instead
import 'package:nnbdc/global.dart';
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

  /// 配置全局音频会话
  static Future<void> configureAudioSession() async {
    if (_audioSessionConfigured) return;

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
    var soundUrl = Util.getWordSoundUrl(word.spell);
    await playSoundByUrl(soundUrl, pronouncePlayer, false);
  }

  /// 播放单词发音
  static Future<void> playPronounceSound2(WordVo word, AudioPlayer player) async {
    var soundUrl = Util.getWordSoundUrl(word.spell);
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

  /// 播放例句发音
  static Future<void> playSentenceSound(String englishDigest) async {
    var soundUrl = Util.getSentenceSoundUrl(englishDigest);
    await playSoundByUrl(soundUrl, AudioPlayer(), true);
  }

  /// 播放例句发音
  static Future<void> playSentenceSound2(String englishDigest, AudioPlayer player) async {
    var soundUrl = Util.getSentenceSoundUrl(englishDigest);
    await playSoundByUrl(soundUrl, player, false, loadTimeoutMs: 5000, playTimeoutMs: 15000);
  }

  /// 播放 ASR 就绪提示音
  static Future<void> playAsrReadyHintSound() async {
    // 使用并发播放模式，音量调低，不阻塞 ASR 启动
    unawaited(playAssetSoundConcurrent('asr_ready_hint.mp3', 1.0, 0.4));
  }

  static Future<void> playSoundByUrl(String soundUrl, AudioPlayer player, bool disposeWhenFinish,
      {int loadTimeoutMs = 3000, int playTimeoutMs = 10000}) async {
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
          if (currentState != PlayerState.stopped && currentState != PlayerState.disposed) {
            await player.stop().timeout(const Duration(milliseconds: 500), onTimeout: () => {});
            await Future.delayed(const Duration(milliseconds: 50));
          }
        } catch (stopError, stackTrace) {
          ErrorHandler.handleError(stopError, stackTrace, logPrefix: '停止音频播放时出错', showToast: false);
        }
      }

      if (PlatformUtils.isWeb) {
        await player.play(UrlSource(soundUrl)).timeout(Duration(milliseconds: loadTimeoutMs));
      } else {
        var file = await DefaultCacheManager().getSingleFile(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
        await player.play(DeviceFileSource(file.path)).timeout(Duration(milliseconds: loadTimeoutMs));
      }
      await player.onPlayerComplete.first.timeout(Duration(milliseconds: playTimeoutMs));
    } on Exception catch (e, stackTrace) {
      ErrorHandler.handleAudioError(e, stackTrace, audioType: 'url:$soundUrl');
    } finally {
      if (disposeWhenFinish) {
        try {
          await player.dispose();
        } catch (e, stackTrace) {
          ErrorHandler.handleError(e, stackTrace, logPrefix: '释放音频播放器时出错', showToast: false);
        }
      }
    }
  }

  /// 播放资产音效（同步模式）
  static Future<void> playAssetSound(
      String soundFileName, double speed, double volume, int timeoutInMilliSeconds, int sleepAfterPlayInMilliSeconds) async {
    final player = AudioPlayer();
    try {
      player.setPlaybackRate(speed);
      player.setVolume(volume);
      await player.play(AssetSource('audio/$soundFileName')).timeout(const Duration(milliseconds: 3000));
      await player.onPlayerComplete.first.timeout(Duration(milliseconds: timeoutInMilliSeconds));
      await Future.delayed(Duration(milliseconds: sleepAfterPlayInMilliSeconds));
    } on TimeoutException catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放音效超时: $soundFileName', showToast: false);
    } catch (e, st) {
      ErrorHandler.handleError(e, st, logPrefix: '播放音效出错: $soundFileName', showToast: false);
    } finally {
      player.dispose();
    }
  }

  /// 并发播放音效
  static Future<void> playAssetSoundConcurrent(String soundFileName, double speed, double volume) {
    final pool = _sfxPools.putIfAbsent(soundFileName, () => [AudioPlayer()]);
    AudioPlayer? player;
    final now = DateTime.now();

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
      Global.logger.d('🔊 [Audio] Pool expanded for $soundFileName: ${pool.length}');
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
        player.stop();
      }
      player.setPlaybackRate(speed);
      player.setVolume(volume);

      await player.play(AssetSource('audio/$soundFileName'));

      if (PlatformUtils.isAndroid) {
        final completer = Completer<void>();
        late StreamSubscription stateSubscription;
        stateSubscription = player.onPlayerStateChanged.listen((state) {
          if (state == PlayerState.completed || state == PlayerState.stopped) {
            if (!completer.isCompleted) completer.complete();
          }
        });
        await Future.any([
          player.onPlayerComplete.first,
          completer.future,
          Future.delayed(const Duration(milliseconds: 1500)),
        ]);
        await stateSubscription.cancel();
      } else {
        await player.onPlayerComplete.first;
      }
    } on Exception catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放后台音效出错: $soundFileName', showToast: false);
    }
  }

  /// 播放音效（限定最大奖励时长）
  static Future<void> playAssetSoundCut(String soundFileName, double speed, double volume, Duration maxPlay) async {
    final pool = _sfxPools.putIfAbsent(soundFileName, () => [AudioPlayer()]);
    AudioPlayer? player;
    final now = DateTime.now();

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
