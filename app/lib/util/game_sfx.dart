import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/sound.dart';

/// 音效种类。
enum SfxKind { hit, throwWhoosh, cry, step }

/// 一类音效的混音规则。
class _SfxRule {
  const _SfxRule(this.file, this.minGapMs, this.volume, {this.varySpeed = true});

  /// 相对 `assets/audio/` 的路径。
  final String file;

  /// 两次发声之间的最小间隔。比这更密的直接丢掉——不是为了省资源，
  /// 而是几十毫秒内连响两次只会糊成一团，听不出是两下。
  final int minGapMs;

  final double volume;

  /// 是否参与 ±8% 的随机变调。
  ///
  /// 机械音效开着好（避免几十次一模一样的机枪感），但**人声不能开**：
  /// Android 上 `setSpeed` 走 ExoPlayer 的 Sonic 时间伸缩，对语音容易产生金属味伪影，
  /// 听感就是「失真」。
  final bool varySpeed;
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

  // 每类音效一个常驻播放器，重触发靠 seek(0)。
  //
  // `minGapMs` 定的是**占空比**：某类音效「在响的时间」占整条时间线的比例。
  // 这一条是实测出来的——原来只按「别把上一声截断」定间隔（≥音效时长），
  // 结果四个音效的占空比分别是 命中 70%、投掷 59%、哭声 66%、脚步 78%：
  // 单个听都很好，混在一起就成了一条连绵不断的音墙，**尤其哭声像卡带循环**
  // （在我 Mac 上单独播一次很好听，进游戏却"不对"，原因就在这里）。
  //
  // 目标是让每类音效成为**标点**而不是底噪，占空比压到 15%~35%：
  //
  //   音效      时长      间隔      发声      占空比
  //   命中      265ms     900ms     1.03/s    27%
  //   投掷      223ms    1100ms     0.88/s    20%
  //   哭声      500ms    1400ms     0.74/s    37%   ← 人声要听得清，给得最宽
  //   脚步      197ms    1200ms     0.88/s    17%
  //
  // 总发声量从 11.0 次/秒 降到 3.5 次/秒。改动前务必用 tools/ 里那套模拟脚本复算占空比，
  // 不要凭感觉调——「间隔不小于音效时长」只是下限，不是目标值。
  // 音量上限之和必须留出余量：四类音效各有独立播放器、**会同时发声**，
  // 系统混音是把它们相加的。素材峰值已归一化到 -6dBFS（0.5），所以
  //   最坏情况峰值 = 0.5 × (0.42+0.26+0.59+0.23=1.50) = 0.75
  // 还有约 2.5dB 富余，不会削波。改动前务必把这一行重算一遍——
  // 之前四者之和是 1.97、素材又贴近满刻度，最坏冲到 1.77（+4.9dB 超满刻度），必然失真。
  static const Map<SfxKind, _SfxRule> _rules = {
    SfxKind.hit: _SfxRule('monster/hit_bonk.wav', 900, 0.42),
    SfxKind.throwWhoosh: _SfxRule('monster/throw_whoosh.wav', 1100, 0.26),
    SfxKind.cry: _SfxRule('monster/cry_whimper.wav', 1400, 0.59, varySpeed: false),
    SfxKind.step: _SfxRule('monster/flee_step.wav', 1200, 0.23),
  };

  final Map<SfxKind, ja.AudioPlayer> _players = {};
  final Map<SfxKind, int> _lastPlayedMs = {};
  final math.Random _rng = math.Random();
  bool _prewarmed = false;

  /// 诊断开关：只放行这里列出的音效种类。
  ///
  /// 这不是托底，是**隔离变量**用的入口——音效问题往往只在「多路混在一起」时才暴露，
  /// 一次只留一路才能判断到底是这一路本身不对，还是混音/编排的问题。
  /// 排查完把这行改回 `SfxKind.values` 全部放行即可。
  static const Set<SfxKind> _enabled = {SfxKind.cry};

  /// 某类音效的资源路径。给契约测试用，避免测试再抄一份文件名。
  static String assetPathOf(SfxKind kind) => 'assets/audio/${_rules[kind]!.file}';

  /// 预加载四路播放器。进页面时调用一次；不预加载的话第一次命中要等解码，声音会迟到。
  ///
  /// **先清资源缓存**，这一步是血的教训：
  /// just_audio 会把 Flutter 资源复制到 `cache/just_audio_cache/` 下播放，而且
  /// **资源内容变了它不会失效**（缓存路径只由资源路径决定，不带版本）。
  /// 实测后果——连装五版新音效，手机上播的一直是最早那份：
  /// 缓存里的 cry_whimper.wav 是 780ms、md5 与当初提交的旧合成版一字不差，
  /// 而 APK 内早已是 500ms 的 AI 生成版。听感上所有「音色不对/失真」的反馈，
  /// 其实都是在评价一个早就该被替换掉的文件。
  /// 官方为此提供了静态方法（注释原文：call this when the app's assets have changed
  /// to force assets to be re-fetched from the asset bundle），所以每次启动清一次。
  Future<void> prewarm() async {
    if (_prewarmed || PlatformUtils.isTesting || PlatformUtils.isWeb) return;
    _prewarmed = true;
    try {
      await ja.AudioPlayer.clearAssetCache();
    } on PathNotFoundException {
      // 首次运行时缓存目录还不存在，本来就没东西要清。这是**正常情况**，不是错误。
      // （实测踩过：不区分地让它抛出去，异常会从 prewarm() 冒到调用方，
      //   结果四路播放器一个都没建起来，直接彻底没声音。）
    }
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
    if (!_enabled.contains(kind)) return;
    final ja.AudioPlayer? player = _players[kind];
    if (player == null) return; // 还没预加载好，这次就不发声

    final _SfxRule rule = _rules[kind]!;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? last = _lastPlayedMs[kind];
    if (last != null && now - last < rule.minGapMs) return;
    _lastPlayedMs[kind] = now;

    final double speed =
        rule.varySpeed ? 1.0 + (_rng.nextDouble() * 2 - 1) * 0.08 : 1.0;
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
