import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/error_handler.dart';
// Avoid direct dart:io Platform on web; use PlatformUtils instead
import 'package:nnbdc/global.dart';

import '../api/vo.dart';

class SoundUtil {
  static AudioPlayer? _pronouncePlayer;
  static bool _webAudioUnlocked = false;
  static bool _webUnlockInProgress = false;

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
    await playSoundByUrl(soundUrl, player, false);
  }

  /// 播放单词发音
  static Future<void> playPronounceSoundBySpell(String spell) async {
    var soundUrl = Util.getWordSoundUrl(spell);
    await playSoundByUrl(soundUrl, AudioPlayer(), true);
  }

  /// 播放单词发音，使用已存在的AudioPlayer实例
  static Future<void> playPronounceSoundBySpell2(String spell, AudioPlayer player) async {
    var soundUrl = Util.getWordSoundUrl(spell);
    await playSoundByUrl(soundUrl, player, false);
  }

  /// 播放例句发音
  static Future<void> playSentenceSound(String englishDigest) async {
    var soundUrl = Util.getSentenceSoundUrl(englishDigest);
    await playSoundByUrl(soundUrl, AudioPlayer(), true);
  }

  /// 播放例句发音
  static Future<void> playSentenceSound2(String englishDigest, AudioPlayer player) async {
    var soundUrl = Util.getSentenceSoundUrl(englishDigest);
    await playSoundByUrl(soundUrl, player, false);
  }

  static Future<void> playSoundByUrl(String soundUrl, AudioPlayer player, bool disposeWhenFinish) async {

    try {
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
            await player.stop();
            // 添加短暂延迟，确保播放器完全停止，避免新旧音频重叠产生爆音
            // 使用固定延迟比等待状态变化更可靠，因为 stop() 后状态可能立即变为停止
            await Future.delayed(const Duration(milliseconds: 50));
          }
        } catch (stopError, stackTrace) {
          ErrorHandler.handleError(stopError, stackTrace, logPrefix: '停止音频播放时出错', showToast: false);
        }
      }

      if (PlatformUtils.isWeb) {
        Global.logger.d('Web audio play url: $soundUrl');
        await player.play(UrlSource(soundUrl));
      } else {
        var file = await DefaultCacheManager().getSingleFile(soundUrl);
        await player.play(DeviceFileSource(file.path));
      }

      // 等待播放完成
      await player.onPlayerComplete.first;
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
            },
          ),
        ));
      }

      // 使用独立播放器，不需要停止其他播放

      if (PlatformUtils.isWeb) {
        Global.logger.d('Web audio play url: $soundUrl');
        await player.play(UrlSource(soundUrl));
      } else {
        var file = await DefaultCacheManager().getSingleFile(soundUrl);
        await player.play(DeviceFileSource(file.path));
      }

      // 等待播放完成
      await player.onPlayerComplete.first;
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

  static Future<void> playAssetSound(String soundFileName, double speed, double volume) async {

    var player = AudioPlayer();
    try {
      // 在 iOS 上设置 AudioContext 以支持混音
      if (PlatformUtils.isIOS) {
        await player.setAudioContext(AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.allowBluetooth,
            },
          ),
        ));
      }

      await player.setPlaybackRate(speed);
      await player.setVolume(volume);

      // 添加播放状态监听
      player.onPlayerStateChanged.listen((state) {
        // 音效播放状态变化
      });

      // 修复路径问题：audioplayers 会自动添加 assets/ 前缀，所以只需要 audio/ 路径
      await player.play(AssetSource('audio/$soundFileName'));

      // 等待播放完成，避免立即释放播放器
      await player.onPlayerComplete.first;

      // 添加一个小延迟确保声音完全播放
      await Future.delayed(Duration(milliseconds: 100));
    } on Exception catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放音效出错', showToast: false);
    } finally {
      player.dispose();
    }
  }

  /// 并发播放音效（不等待播放完成，立即返回，支持多个音频同时播放）
  /// 音频会在后台播放完成并自动释放播放器
  /// 返回 Future，可用于跟踪播放状态
  static Future<void> playAssetSoundConcurrent(String soundFileName, double speed, double volume) {
    var player = AudioPlayer();
    
    // 在后台异步处理播放和释放，不阻塞调用者
    return _playAssetSoundInBackground(player, soundFileName, speed, volume).catchError((error, stackTrace) {
      ErrorHandler.handleError(error, stackTrace, logPrefix: '并发播放音效出错', showToast: false);
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
      // iOS 上不设置 AudioContext，保持原有行为以确保正常工作
      // Android 上也不设置 AudioContext，与 playAssetSound 保持一致，确保能正常播放
      // 虽然理论上 Android 在录音时需要 AudioContext 才能在录音时播放音效，
      // 但实际测试发现设置 AudioContext 会导致音频无法播放，而不设置反而能正常工作
      
      await player.setPlaybackRate(speed);
      await player.setVolume(volume);

      // 添加播放状态监听
      player.onPlayerStateChanged.listen((state) {
        // 音效播放状态变化
      });

      // 修复路径问题：audioplayers 会自动添加 assets/ 前缀，所以只需要 audio/ 路径
      await player.play(AssetSource('audio/$soundFileName'));

      // 等待播放完成，避免立即释放播放器
      // 在 Android 上，如果 onPlayerComplete 不触发，使用超时机制确保 Future 能够完成
      if (PlatformUtils.isAndroid) {
        // 使用 Future.any 添加超时保护，确保即使 onPlayerComplete 不触发，Future 也能完成
        // 超时时间设置为 3 秒（correct.mp3 通常播放时间较短）
        await Future.any([
          player.onPlayerComplete.first,
          Future.delayed(Duration(milliseconds: 3000)),
        ]);
      } else {
        await player.onPlayerComplete.first;
      }

      // 添加一个小延迟确保声音完全播放
      await Future.delayed(Duration(milliseconds: 100));
    } on Exception catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放音效出错', showToast: false);
    } finally {
      player.dispose();
    }
  }

  /// 播放音效（限定最大奖励时长），用于跳过音效结尾的静音段
  static Future<void> playAssetSoundCut(String soundFileName, double speed, double volume, Duration maxPlay) async {

    var player = AudioPlayer();
    try {
      if (PlatformUtils.isIOS) {
        await player.setAudioContext(AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.allowBluetooth,
            },
          ),
        ));
      }

      await player.setPlaybackRate(speed);
      await player.setVolume(volume);

      player.onPlayerStateChanged.listen((state) {});

      await player.play(AssetSource('audio/$soundFileName'));

      // 仅等待到播放完成或达到限定时长
      await Future.any([
        player.onPlayerComplete.first,
        Future.delayed(maxPlay),
      ]);

      // 若未完成则手动停止
      try {
        await player.stop();
      } catch (e, stackTrace) {
        // 停止播放器失败不影响流程，但需要记录
        Global.logger.w('停止AudioPlayer失败', error: e, stackTrace: stackTrace);
      }
      await Future.delayed(Duration(milliseconds: 60));
    } on Exception catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放音效出错', showToast: false);
    } finally {
      player.dispose();
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
}
