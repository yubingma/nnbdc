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
  const _SfxRule(this.file, this.minGapMs, this.volume, this.durationMs,
      {this.varySpeed = true});

  /// 相对 `assets/audio/` 的路径。
  final String file;

  /// 两次发声之间的最小间隔。
  ///
  /// 它有两个作用：
  /// 1. **决定占空比**（这类音效「在响的时间」占整条时间线的比例）——
  ///    只按「别把上一声截断」来定是不够的，那样四类音效的占空比会到 59~78%，
  ///    混在一起是一条连绵的音墙，谁也听不清；
  /// 2. **保证不截断**：必须 ≥ 音效时长 ÷ 最慢变调速度，否则重触发会把上一声拦腰截断。
  ///    这条由 app/test/monster_sfx_test.dart 断言。
  final int minGapMs;

  final double volume;

  /// 音效本身时长（毫秒），必须与素材一致——app/test/monster_sfx_test.dart 会断言。
  final int durationMs;

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
/// 需求是十几次/秒——超了好几倍。实测塞进去的后果是：
/// 播放器被强行抢用，声音**被掐断在 103ms**（logcat 里 `AudioTrack stop ...
/// 4532 frames delivered`，而音效本身是 110~780ms），并伴随反复重建解码器。
///
/// 所以这里走一条适配游戏的路：**每类音效一个常驻播放器，资源只在预加载时装载一次，
/// 之后靠 `seek(0)` 重触发**。没有换载、不会互相抢、也不会被掐断。
///
/// ## 混音策略
///
/// 1. **同类事件时间去重**：比 `minGapMs` 更密的直接丢；
/// 2. **每次随机变调 ±8%**：避免几十次一模一样的机械重复感。
///    变调走 `setSpeed` 而不是准备多个不同音高的文件——多文件会逼播放器反复换载；
/// 3. **按远近调音量**：远的轻、近的重。这是「乱但有层次」的关键，
///    也是唯一能让 16 只小怪不吵成一团的办法。
///
/// 试过但**放弃**的做法：给哭声做多路「合唱」（3 路 × 每路 1/3 音量），
/// 想让一群小怪同时在哭。结论是行不通的：只要两声重叠，就一定有
/// 「间隔 < 时长」，也就一定有「占空比 > 100%」——**哭声一刻不停**，
/// 实测 15 秒响 32 次、占空比 107%，用户反馈「太吵」。
/// 单个事件流里，「同时听到几只」和「一刻不停」是同一件事。
/// 想要「一群在哭」的听感，正确做法是另做一条低音量的环境底噪。
class GameSfx {
  GameSfx._();

  static final GameSfx instance = GameSfx._();

  // 音量上限必须留出余量：四类音效各有独立播放器、**会同时发声**，
  // 系统混音是把它们相加的。素材峰值已归一化到 -6dBFS（0.5），所以
  //   最坏情况峰值 = 0.5 × (0.42 + 0.26 + 0.23 + 0.59 = 1.50) = 0.75
  // 还有约 2.5dB 富余，不会削波。改动前务必把这一行重算一遍——
  // 曾经四者之和是 1.97、素材又贴近满刻度，最坏冲到 1.77（+4.9dB 超满刻度），必然失真。
  static const Map<SfxKind, _SfxRule> _rules = {
    SfxKind.hit: _SfxRule('monster/hit_bonk.wav', 900, 0.42, 265),
    SfxKind.throwWhoosh: _SfxRule('monster/throw_whoosh.wav', 1100, 0.26, 223),
    SfxKind.cry: _SfxRule('monster/cry_whimper.wav', 1400, 0.59, 446,
        varySpeed: false),
    SfxKind.step: _SfxRule('monster/flee_step.wav', 1200, 0.23, 197),
  };

  /// 诊断开关：只放行这里列出的音效种类。
  ///
  /// 这不是托底，是**隔离变量**用的入口——音效问题往往只在「多路混在一起」时才暴露，
  /// 一次只留一路才能判断到底是这一路本身不对，还是混音/编排的问题。
  /// 排查完把这行改回 `{...SfxKind.values}` 全部放行即可。
  static const Set<SfxKind> _enabled = {...SfxKind.values};

  final Map<SfxKind, ja.AudioPlayer> _players = {};
  final Map<SfxKind, int> _lastPlayedMs = {};
  final math.Random _rng = math.Random();
  bool _prewarmed = false;

  /// 某类音效的资源路径。给契约测试用，避免测试再抄一份文件名。
  static String assetPathOf(SfxKind kind) => 'assets/audio/${_rules[kind]!.file}';

  /// 某类音效在规则表里登记的时长（毫秒）。同样给契约测试用。
  static int durationMsOf(SfxKind kind) => _rules[kind]!.durationMs;

  /// 某类音效的最小间隔（毫秒）。给契约测试用。
  static int minGapMsOf(SfxKind kind) => _rules[kind]!.minGapMs;

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
  /// 三步之间的耗时只有几毫秒，而 `minGapMs` 至少 900ms，所以不会互相踩。
  Future<void> _retrigger(ja.AudioPlayer player, double speed, double volume) async {
    await player.setSpeed(speed);
    await player.setVolume(volume);
    await player.seek(Duration.zero);
    unawaited(player.play());
  }
}
