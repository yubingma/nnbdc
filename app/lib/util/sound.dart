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

import 'package:flutter/foundation.dart';
import '../api/vo.dart';

class SoundUtil {
  static ja.AudioPlayer? _pronouncePlayer;
  static bool _webAudioUnlocked = false;
  static bool _webUnlockInProgress = false;
  static bool _audioSessionConfigured = false;
  static String _currentSessionCategory = 'none';
  static String get currentSessionCategory => _currentSessionCategory;

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
    } catch (e) {
      Global.logger.e('SoundUtil: 配置全局音频会话失败: $e');
    } finally {
      _configureFuture = null;
    }
  }

  /// 切换为高保真纯播放模式 (无麦克风占用，无回声消除滤波，高动态范围，高保真度)
  static Future<void> usePlaybackCategory() async {
    if (PlatformUtils.isWeb) return;
    if (_currentSessionCategory == 'playback') {
      Global.logger.d('🔊 [SoundUtil] 当前音频分类已是 playback，无须重复配置');
      debugPrint('🔊 [SoundUtil] 当前音频分类已是 playback，无须重复配置');
      return;
    }
    try {
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
      ));
      // Preferred sample rate setting removed (unsupported in audio_session)
      _currentSessionCategory = 'playback';
      Global.logger.i('🔊 [SoundUtil] 成功切换音频会话为: playback (高保真播放，解除麦克风占用和回声过滤)');
      debugPrint('🔊 [SoundUtil] 成功切换音频会话为: playback (高保真播放，解除麦克风占用和回声过滤)');
    } catch (e) {
      Global.logger.e('SoundUtil: 切换高保真播放模式失败: $e');
    }
  }

  /// 切换为录音与播放并存模式 (用于 ASR 语音识别场景，匹配 iOS 原生配置，优化蓝牙高保真度)
  static Future<void> usePlayAndRecordCategory() async {
    if (PlatformUtils.isWeb) return;
    if (_currentSessionCategory == 'playAndRecord') {
      Global.logger.d('🔊 [SoundUtil] 当前音频分类已是 playAndRecord，无须重复配置');
      debugPrint('🔊 [SoundUtil] 当前音频分类已是 playAndRecord，无须重复配置');
      return;
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
      ));
      // Preferred sample rate setting removed (unsupported in audio_session)
      _currentSessionCategory = 'playAndRecord';
      Global.logger.i('🔊 [SoundUtil] 成功切换音频会话为: playAndRecord (录音与播放并存，启用 A2DP 蓝牙高保真)');
      debugPrint('🔊 [SoundUtil] 成功切换音频会话为: playAndRecord (录音与播放并存，启用 A2DP 蓝牙高保真)');
    } catch (e) {
      Global.logger.e('SoundUtil: 切换为录放模式失败: $e');
    }
  }

  static void _prewarmSfx(List<String> files) {
    for (var f in files) {
      _sfxPools.putIfAbsent(f, () {
        final p = ja.AudioPlayer();
        p.setAsset('assets/audio/$f').catchError((e) {
          Global.logger.w('SoundUtil: 预热音效失败 assets/audio/$f: $e');
          return null;
        });
        return [p];
      });
    }
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
  static Future<void> playPronounceSound2(WordVo word, ja.AudioPlayer player) async {
    var soundUrl = Util.getWordSoundUrl(word.spell, word: word);
    Global.logger.d('🔊 播放发音 (指定播放器) [Spell: ${word.spell}, UpdateTime: ${word.updateTime}] URL: $soundUrl');
    await playSoundByUrl(soundUrl, player, false, loadTimeoutMs: 3000, playTimeoutMs: 5000);
  }

  /// 播放单词发音 (按拼写)
  static Future<void> playPronounceSoundBySpell(String spell) async {
    var soundUrl = Util.getWordSoundUrl(spell);
    await playSoundByUrl(soundUrl, ja.AudioPlayer(), true);
  }

  /// 播放单词发音，使用已存在的播放器实例
  static Future<void> playPronounceSoundBySpell2(String spell, ja.AudioPlayer player, {double speed = 1.0}) async {
    var soundUrl = Util.getWordSoundUrl(spell);
    await playSoundByUrl(soundUrl, player, false, loadTimeoutMs: 3000, playTimeoutMs: 10000, speed: speed);
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
  static Future<void> playSentenceSound2(String englishDigest, ja.AudioPlayer player, {double speed = 1.0}) async {
    var soundUrl = Util.getSentenceSoundUrl(englishDigest);
    await playSoundByUrl(soundUrl, player, false, loadTimeoutMs: 7000, playTimeoutMs: 20000, speed: speed);
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
      {int loadTimeoutMs = 3000, int playTimeoutMs = 10000, double speed = 1.0}) async {
    try {
      if (!_audioSessionConfigured) {
        await configureAudioSession();
      }
      if (PlatformUtils.isWeb) {
        await _ensureWebAudioUnlocked();
      }

      final DateTime startTime = DateTime.now();
      Global.logger.i('🔊 [SoundUtil] 触发播放时的实际音频会话分类为: $_currentSessionCategory | 播放 URL: $soundUrl | 倍速: $speed');
      debugPrint('🔊 [SoundUtil] 触发播放时的实际音频会话分类为: $_currentSessionCategory | 播放 URL: $soundUrl | 倍速: $speed');

      // 设置源
      if (PlatformUtils.isWeb) {
        await player.setUrl(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
      } else {
        final cacheManager = DefaultCacheManager();
        FileInfo? fileInfo = await cacheManager.getFileFromCache(soundUrl);
        if (fileInfo != null) {
          await player.setFilePath(fileInfo.file.path).timeout(Duration(milliseconds: loadTimeoutMs));
        } else {
          var file = await cacheManager.getSingleFile(soundUrl).timeout(Duration(milliseconds: loadTimeoutMs));
          await player.setFilePath(file.path).timeout(Duration(milliseconds: loadTimeoutMs));
        }
      }

      // 设置倍速并播放
      await player.setSpeed(speed);
      await player.play();
      
      // 显式等待播放完成或被手动停止 (idle)
      // 在某些平台或特定条件下，await player.play() 可能会提前返回
      await player.playerStateStream
          .firstWhere((state) => 
              state.processingState == ja.ProcessingState.completed || 
              state.processingState == ja.ProcessingState.idle)
          .timeout(Duration(milliseconds: playTimeoutMs));

      final int elapsed = DateTime.now().difference(startTime).inMilliseconds;
      Global.logger.d('~~~~~ SoundUtil(ja): 播放完成，逻辑耗时: ${elapsed}ms');
    } catch (e, stackTrace) {
      final errorStr = e.toString();
      // 过滤掉 "Connection aborted" 错误，这通常是因为在旧的音频还在加载时开始了新的播放
      if (errorStr.contains('Connection aborted') || errorStr.contains('abort')) {
        Global.logger.i('~~~~~ SoundUtil(ja): 播放被中止 (可能由于开始了新的播放): $soundUrl');
        return;
      }
      if (e is Exception) {
        ErrorHandler.handleAudioError(e, stackTrace, audioType: 'ja_url:$soundUrl');
      } else {
        Global.logger.e('SoundUtil: 非 Exception 类型的音频播放错误: $e', error: e, stackTrace: stackTrace);
      }
    } finally {
      if (disposeWhenFinish) {
        await player.dispose();
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
    Global.logger.i("🔊 [SoundUtil] 触发播放音效时的实际音频会话分类为: $_currentSessionCategory | 音效名: $soundFileName");
    debugPrint("🔊 [SoundUtil] 触发播放音效时的实际音频会话分类为: $_currentSessionCategory | 音效名: $soundFileName");
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
      ErrorHandler.handleError(e, st, logPrefix: '播放音效出错: $soundFileName', showToast: false);
    }
  }

  /// 并发播放音效
  static Future<void> playAssetSoundConcurrent(String soundFileName, double speed, double volume) async {
    await configureAudioSession();
    // Ensure we are in high‑fidelity playback mode for short UI feedback sounds,
    // but DO NOT switch if we are currently using playAndRecord (e.g. during ASR active)
    // to prevent tearing down the iOS microphone stream/audio engine.
    if (_currentSessionCategory != 'playAndRecord') {
      await usePlaybackCategory();
    }
    if (PlatformUtils.isWeb) return;
    Global.logger.i("🔊 [SoundUtil] 触发并发播放音效时的实际音频会话分类为: $_currentSessionCategory | 音效名: $soundFileName");
    debugPrint("🔊 [SoundUtil] 触发并发播放音效时的实际音频会话分类为: $_currentSessionCategory | 音效名: $soundFileName");

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
      ErrorHandler.handleError(e, stackTrace, logPrefix: '播放音效出错: $soundFileName', showToast: false);
    } finally {
      await player.stop();
    }
  }

  /// 播放音效（限定最大奖励时长）
  static Future<void> playAssetSoundCut(String soundFileName, double speed, double volume, Duration maxPlay) async {
    if (!_audioSessionConfigured) {
      await configureAudioSession();
    }
    Global.logger.i("🔊 [SoundUtil] 触发被裁剪音效时的实际音频会话分类为: $_currentSessionCategory | 音效名: $soundFileName");
    debugPrint("🔊 [SoundUtil] 触发被裁剪音效时的实际音频会话分类为: $_currentSessionCategory | 音效名: $soundFileName");
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
