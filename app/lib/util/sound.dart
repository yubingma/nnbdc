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
  static final Map<String, AudioPlayer> _sfxPlayers = {};

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
      
      // 预热常用音效播放器，避免游戏过程中首次创建导致的 250ms 级卡顿
      _prewarmSfx(['thud.mp3', 'correct.mp3', 'fail.mp3']);
    } catch (e) {
      Global.logger.e('SoundUtil: 配置全局音频会话失败: $e');
    }
  }

  static void _prewarmSfx(List<String> files) {
    for (var f in files) {
      _sfxPlayers.putIfAbsent(f, () {
        final p = AudioPlayer();
        // 设置静态 Source 预加载（可选，取决于插件版本支持）
        p.setSource(AssetSource('audio/$f')).catchError((_) {});
        return p;
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

  /// 播放单词发音
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

  static Future<void> playSoundByUrl(String soundUrl, AudioPlayer player, bool disposeWhenFinish,
      {int loadTimeoutMs = 3000, int playTimeoutMs = 10000}) async {
    try {
      // 核心优化：仅配置一次音频会话，避免频繁切换导致的咔哒噪音（由随身听反馈发现）
      if (!_audioSessionConfigured) {
        await configureAudioSession();
      }

      await player.setVolume(1.0);

      // player 为 AudioPlayerFactory.create() 产物（真实或 Mock），无需判空
      if (PlatformUtils.isWeb) {
        await _ensureWebAudioUnlocked();
      }

      // 添加播放状态监听
      player.onPlayerStateChanged.listen((state) {
        // 音频播放状态变化
      });

      // 只有在使用共享播放器时才停止当前播放（避免中断其他独立播放器的音频）
      // 如果 disposeWhenFinish 为 true，说明使用的是独立播放器，不需要停止
      if (!disposeWhenFinish) {
        try {
          // 先检查当前状态，如果已经是停止状态，就不需要调用 stop()
          final currentState = player.state;
          if (currentState != PlayerState.stopped && currentState != PlayerState.disposed) {
            await player.stop().timeout(const Duration(milliseconds: 500), onTimeout: () => {});
            // 添加短暂延迟，确保播放器完全停止，避免新旧音频重叠产生爆音
            // 使用固定延迟比等待状态变化更可靠，因为 stop() 后状态可能立即变为停止
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
        await player.play(DeviceFileSource(file.path)).timeout(const Duration(milliseconds: 3000));
      }

      // 等待播放完成
      await player.onPlayerComplete.first.timeout(Duration(milliseconds: playTimeoutMs));
    } catch (e, st) {
      ErrorHandler.handleAudioError(e, st, audioType: 'url:$soundUrl');
      try {
        player.stop();
      } catch (stopError, stackTrace) {
        ErrorHandler.handleError(stopError, stackTrace, logPrefix: '停止音频播放时出错', showToast: false);
      }
    } finally {
      if (disposeWhenFinish) {
        try {
          player.dispose();
        } catch (disposeError, stackTrace) {
          ErrorHandler.handleError(disposeError, stackTrace, logPrefix: '释放音频播放器时出错', showToast: false);
        }
      }
    }
  }

  /// 并发播放 URL 音频（使用独立播放器，不等待播放完成，立即返回，支持多个音频同时播放）
  static void playSoundByUrlConcurrent(String soundUrl) {
    var player = AudioPlayer();

    // 在后台异步处理播放和释放，不阻塞调用者
    _playSoundByUrlInBackground(player, soundUrl).catchError((error, stackTrace) {
      ErrorHandler.handleAudioError(error, stackTrace, audioType: 'url:$soundUrl');
    });
  }

  /// 在后台播放 URL 音频并自动释放播放器
  static Future<void> _playSoundByUrlInBackground(AudioPlayer player, String soundUrl) async {
    try {
      if (PlatformUtils.isWeb) {
        await _ensureWebAudioUnlocked();
      }

      // 添加播放状态监听
      player.onPlayerStateChanged.listen((state) {
        // 音频播放状态变化
      });

      // 在 iOS 上设置 AudioContext 以支持混音
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
        try {
          await player.setAudioContext(AudioContext(
            android: AudioContextAndroid(
              usageType: AndroidUsageType.media,
              contentType: AndroidContentType.speech,
              // 使用 none 而不是 gainTransientMayDuck，防止抢占 ASR 麦克风音频焦点导致底层崩溃闪退
              audioFocus: AndroidAudioFocus.none,
            ),
          ));
        } catch (e, st) {
          Global.logger.e('Android setAudioContext 异常', error: e, stackTrace: st);
        }
      }
      await player.setVolume(1.0);

      // 使用独立播放器，不需要停止其他播放

      if (PlatformUtils.isWeb) {
        await player.play(UrlSource(soundUrl)).timeout(const Duration(milliseconds: 3000));
      } else {
        var file = await DefaultCacheManager().getSingleFile(soundUrl).timeout(const Duration(milliseconds: 3000));
        await player.play(DeviceFileSource(file.path)).timeout(const Duration(milliseconds: 3000));
      }

      // 等待播放完成
      await player.onPlayerComplete.first.timeout(const Duration(milliseconds: 10000));
    } catch (e, st) {
      ErrorHandler.handleAudioError(e, st, audioType: 'url:$soundUrl');
      try {
        player.stop();
      } catch (stopError, stackTrace) {
        ErrorHandler.handleError(stopError, stackTrace, logPrefix: '停止音频播放时出错', showToast: false);
      }
    } finally {
      try {
        player.dispose();
      } catch (disposeError, stackTrace) {
        ErrorHandler.handleError(disposeError, stackTrace, logPrefix: '释放音频播放器时出错', showToast: false);
      }
    }
  }

  static Future<void> playAssetSound(
      String soundFileName, double speed, double volume, int timeoutInMilliSeconds, int sleepAfterPlayInMilliSeconds) async {
    var player = AudioPlayer();
    try {
      // 在 iOS 上设置 AudioContext 以支持混音
      if (PlatformUtils.isIOS) {
        await player
            .setAudioContext(AudioContext(
              iOS: AudioContextIOS(
                category: AVAudioSessionCategory.playAndRecord,
                options: {
                  AVAudioSessionOptions.defaultToSpeaker,
                  AVAudioSessionOptions.mixWithOthers,
                  AVAudioSessionOptions.allowBluetooth,
                },
              ),
            ))
            .timeout(const Duration(milliseconds: 5000));
      }

      await player.setPlaybackRate(speed).timeout(const Duration(milliseconds: 5001)); // 故意把超时时间设置的有点区别
      await player.setVolume(volume).timeout(const Duration(milliseconds: 5002));

      // 添加播放状态监听
      player.onPlayerStateChanged.listen((state) {
        // 音效播放状态变化
      });

      // 修复路径问题：audioplayers 会自动添加 assets/ 前缀，所以只需要 audio/ 路径
      await player.play(AssetSource('audio/$soundFileName')).timeout(const Duration(milliseconds: 3000));

      // 等待播放完成，避免立即释放播放器
      await player.onPlayerComplete.first.timeout(Duration(milliseconds: timeoutInMilliSeconds));

      // 睡眠指定时间
      await Future.delayed(Duration(milliseconds: sleepAfterPlayInMilliSeconds));
    } on TimeoutException catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放音效出错1', showToast: false);
    } catch (e, st) {
      ErrorHandler.handleError(e, st, logPrefix: '播放音效出错2', showToast: false);
    } finally {
      player.dispose();
    }
  }

  /// 并发播放音效（不等待播放完成，立即返回，支持多个音频同时播放）
  /// 音频会在后台播放完成并自动释放播放器
  /// 返回 Future，可用于跟踪播放状态
  static Future<void> playAssetSoundConcurrent(String soundFileName, double speed, double volume) {
    final player = _sfxPlayers.putIfAbsent(soundFileName, () => AudioPlayer());
    return _playAssetSoundInBackground(player, soundFileName, speed, volume).catchError((error, stackTrace) {
      ErrorHandler.handleError(error, stackTrace, logPrefix: '并发播放音效出错: $soundFileName', showToast: false);
    });
  }

  /// 在后台播放音效并自动释放播放器
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

      // 修复路径问题：audioplayers 会自动添加 assets/ 前缀，所以只需要 audio/ 路径
      await player.play(AssetSource('audio/$soundFileName'));

      // 等待播放完成，避免立即释放播放器
      // 在 Android 上，如果 onPlayerComplete 不触发，使用播放状态监听 + 超时机制确保 Future 能够完成
      if (PlatformUtils.isAndroid) {
        // 使用播放状态监听来判断是否完成，比单纯等待 onPlayerComplete 更可靠
        // correct.mp3 通常播放时间很短（约 200-500 毫秒），设置 800 毫秒超时足够
        final completer = Completer<void>();
        late StreamSubscription stateSubscription;

        stateSubscription = player.onPlayerStateChanged.listen((state) {
          if (state == PlayerState.completed || state == PlayerState.stopped) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          }
        });

        // 等待播放完成或超时
        await Future.any([
          player.onPlayerComplete.first,
          completer.future,
          Future.delayed(Duration(milliseconds: 800)), // 800 毫秒超时
        ]);

        await stateSubscription.cancel();
      } else {
        await player.onPlayerComplete.first;
      }
    } on Exception catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放后台音效出错: $soundFileName', showToast: false);
    }
  }

  /// 播放音效（限定最大奖励时长），用于跳过音效结尾的静音段
  static Future<void> playAssetSoundCut(String soundFileName, double speed, double volume, Duration maxPlay) async {
    final player = _sfxPlayers.putIfAbsent(soundFileName, () => AudioPlayer());
    try {
      if (player.state == PlayerState.playing) {
        player.stop();
      }

      player.setPlaybackRate(speed);
      player.setVolume(volume);

      // 非等待模式播放
      // ignore: unawaited_futures
      player.play(AssetSource('audio/$soundFileName'));

      // 仅等待到播放完成或达到限定时长
      await Future.any([
        player.onPlayerComplete.first,
        Future.delayed(maxPlay),
      ]);

      if (player.state == PlayerState.playing) {
        player.stop();
      }
      await Future.delayed(const Duration(milliseconds: 20));
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
      // 使用一个独立的播放器，播放极短的提示音以解锁音频（音量调低）
      final AudioPlayer unlockPlayer = AudioPlayer();
      try {
        await unlockPlayer.setVolume(0.0); // 静音播放用于解锁
      } catch (e, stackTrace) {
        // 设置音量失败不影响解锁流程，但需要记录
        Global.logger.w('设置AudioPlayer音量失败', error: e, stackTrace: stackTrace);
      }
      try {
        await unlockPlayer.play(AssetSource('audio/bubble-pop.mp3'));
        // 等待最多 300ms，不阻塞主流程太久
        await Future.any([
          unlockPlayer.onPlayerComplete.first,
          Future.delayed(const Duration(milliseconds: 300)),
        ]);
      } catch (e, st) {
        // 即使解锁失败也不阻断主流程
        Global.logger.w('Web audio unlock attempt failed', error: e, stackTrace: st);
      } finally {
        try {
          await unlockPlayer.stop();
        } catch (e, stackTrace) {
          // 停止播放器失败不影响流程，但需要记录
          Global.logger.w('停止AudioPlayer失败', error: e, stackTrace: stackTrace);
        }
        try {
          await unlockPlayer.dispose();
        } catch (e, stackTrace) {
          // 释放播放器失败不影响流程，但需要记录
          Global.logger.w('释放AudioPlayer失败', error: e, stackTrace: stackTrace);
        }
      }
      _webAudioUnlocked = true;
    } finally {
      _webUnlockInProgress = false;
    }
  }

  /// 播放ASR启动提示音
  static Future<void> playAsrReadyHintSound() async {
    // 使用 playAssetSoundConcurrent 避免设置/重置 AudioContext 导致的切换噪音
    await SoundUtil.playAssetSoundConcurrent('asr_ready_hint.mp3', 1.3, 1.0).catchError((e) {
      Global.logger.i('播放ASR启动提示音失败: $e');
    });
    Global.logger.d('🔔 提示音播放完成，用户可以开始说话');
  }
}
