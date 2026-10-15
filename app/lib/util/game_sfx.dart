import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/sound.dart';

/// 音效种类。
enum SfxKind { hit, throwWhoosh, cry, step }

/// 一类音效的混音规则。
class _SfxRule {
  const _SfxRule(this.file, this.minGapMs, this.volume);

  /// 相对 `assets/audio/` 的路径。
  final String file;

  /// 两次发声之间的最小间隔。比这更密的直接丢掉——不是为了省资源，
  /// 而是几十毫秒内连响两次只会糊成一团，听不出是两下。
  final int minGapMs;

  final double volume;
}

/// 「打哭小馋怪」的音效播放与混音策略。
///
/// ## 为什么不复用学习页的音效池
///
/// [StudyAudioSessionController] 的音效池是**为偶发提示音设计的**：只有 3 个播放器，
/// 且每次播放后把播放器占用整整 1 秒（见其 `_playAssetSound` 里的 busyDuration），
/// 也就是物理上限 **3 次/秒**。而本场景一轮 6.8 秒里有 48 次命中加 48 次投掷，
/// 需求是 15 次/秒上下——超了五倍。实测塞进去的后果是：
/// 播放器被强行抢用，声音**被掐断在 103ms**（logcat 里 `AudioTrack stop ...
/// 4532 frames delivered`，而音效本身是 110~780ms），并伴随反复重建解码器
/// （12 秒 28 次 `ExoPlayerImpl: Init`）。
///
/// 所以这里走一条适配游戏的路：**每类音效一个常驻播放器，资源只在预加载时装载一次，
/// 之后靠 `seek(0)` 重触发**。没有换载、不会互相抢、也不会被掐断。
/// 四类音效四个解码器，与学习页音效池三个是同一量级。
///
/// ## 混音策略
///
/// 1. **同类事件时间去重**：比 `minGapMs` 更密的直接丢；
/// 2. **每次随机变调 ±8%**：避免几十次一模一样的机械重复感。
///    变调走 `setSpeed` 而不是准备多个不同音高的文件——多文件会逼播放器反复换载；
/// 3. **按远近调音量**：远的轻、近的重。这是「乱但有层次」的关键，
///    也是唯一能让 16 只小怪不吵成一团的办法。
///
/// 「被打哭」是重要事件：间隔短、音量明显更高，保证它盖得过背景的噼啪声。
class GameSfx {
  GameSfx._();

  static final GameSfx instance = GameSfx._();

  static const Map<SfxKind, _SfxRule> _rules = {
    SfxKind.hit: _SfxRule('monster/hit_bonk.wav', 130, 0.55),
    SfxKind.throwWhoosh: _SfxRule('monster/throw_whoosh.wav', 150, 0.34),
    SfxKind.cry: _SfxRule('monster/cry_whimper.wav', 420, 0.78),
    SfxKind.step: _SfxRule('monster/flee_step.wav', 110, 0.30),
  };

  final Map<SfxKind, ja.AudioPlayer> _players = {};
  final Map<SfxKind, int> _lastPlayedMs = {};
  final math.Random _rng = math.Random();
  bool _prewarmed = false;

  /// 某类音效的资源路径。给契约测试用，避免测试再抄一份文件名。
  static String assetPathOf(SfxKind kind) => 'assets/audio/${_rules[kind]!.file}';

  /// 预加载四路播放器。进页面时调用一次；不预加载的话第一次命中要等解码，声音会迟到。
  Future<void> prewarm() async {
    if (_prewarmed || PlatformUtils.isTesting || PlatformUtils.isWeb) return;
    _prewarmed = true;
    for (final SfxKind kind in SfxKind.values) {
      try {
        final ja.AudioPlayer player = SoundUtil.createAudioPlayer();
        await player.setAsset(assetPathOf(kind));
        _players[kind] = player;
      } catch (e) {
        // 装载失败就让这一类没声音，同时把原因喊出来——不静默吞掉
        debugPrint('🔊 [GameSfx] ${kind.name} 预加载失败: $e');
      }
    }
  }

  /// 播放一次音效。[nearness] 0 = 最远、1 = 最近，决定音量。
  void play(SfxKind kind, {required double nearness}) {
    if (PlatformUtils.isTesting || PlatformUtils.isWeb) return;
    final ja.AudioPlayer? player = _players[kind];
    if (player == null) return; // 还没预加载好，这次就不发声

    final _SfxRule rule = _rules[kind]!;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? last = _lastPlayedMs[kind];
    if (last != null && now - last < rule.minGapMs) return;
    _lastPlayedMs[kind] = now;

    final double speed = 1.0 + (_rng.nextDouble() * 2 - 1) * 0.08;
    final double volume =
        (rule.volume * (0.30 + 0.70 * nearness.clamp(0.0, 1.0))).clamp(0.0, 1.0);
    unawaited(_retrigger(player, speed, volume));
  }

  /// 不 await：[just_audio] 的 play() 会一直挂到这一声放完，await 它没有意义。
  /// 三步之间的耗时只有几毫秒，而 `minGapMs` 至少 110ms，所以不会互相踩。
  Future<void> _retrigger(ja.AudioPlayer player, double speed, double volume) async {
    await player.setSpeed(speed);
    await player.setVolume(volume);
    await player.seek(Duration.zero);
    unawaited(player.play());
  }
}
