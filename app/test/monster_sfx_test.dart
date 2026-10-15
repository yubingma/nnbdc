import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/game_sfx.dart';

/// 「打哭小馋怪」音效契约测试。
///
/// 重点是**规则表里的文件名必须真的存在**：写错了不会编译报错、
/// 界面也不会报错，只是打起来一片寂静——这类错误只能靠断言抓。
void main() {
  final File pubspec = File('pubspec.yaml');

  test('pubspec 声明了音效子目录（assets 声明不递归，子目录必须单独写）', () {
    final String text = pubspec.readAsStringSync();
    expect(
      text.contains(RegExp(r'^\s*-\s*assets/audio/monster/\s*$', multiLine: true)),
      isTrue,
      reason: 'pubspec.yaml 的 assets 声明完全不递归，assets/audio/monster/ 必须单独声明；'
          '漏了会静默跳过——代码报 Unable to load asset，而编译、静态检查、单元测试全通过',
    );
  });

  test('规则表引用的每个音效文件都真实存在', () {
    for (final SfxKind kind in SfxKind.values) {
      final String path = GameSfx.assetPathOf(kind);
      expect(File(path).existsSync(), isTrue,
          reason: '$kind 指向 $path，但这个文件不存在');
    }
  });

  test('音效都是 44.1kHz 单声道 16bit PCM（跨 iOS/Android 最稳的编码）', () {
    for (final SfxKind kind in SfxKind.values) {
      final File f = File(GameSfx.assetPathOf(kind));
      final List<int> b = f.readAsBytesSync();
      // WAV 头：0-3 "RIFF"，8-11 "WAVE"，20-21 音频格式(1=PCM)，22-23 声道数，24-27 采样率
      expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(b.sublist(8, 12)), 'WAVE');
      final int channels = b[22] | (b[23] << 8);
      final int sampleRate =
          b[24] | (b[25] << 8) | (b[26] << 16) | (b[27] << 24);
      expect(channels, 1, reason: '$kind 不是单声道');
      expect(sampleRate, 44100, reason: '$kind 不是 44.1kHz');
      expect(f.lengthSync(), lessThan(80 * 1024), reason: '$kind 体积过大');
    }
  });

  test('规则表里写的时长必须与素材实际时长一致', () {
    // 这个时长不是装饰：播放层用它算「某一路忙到什么时候」，
    // 写小了会在声音还没放完时又占用同一路（拦腰截断），写大了会白占一路。
    // 素材换了却忘了改这里，只会表现为「偶尔有点别扭」，很难查，所以断言住。
    for (final SfxKind kind in SfxKind.values) {
      final File f = File(GameSfx.assetPathOf(kind));
      final int dataBytes = f.lengthSync() - 44;   // WAV 头 44 字节
      final int actualMs = (dataBytes / 2 / 44100 * 1000).round();
      expect(GameSfx.durationMsOf(kind), closeTo(actualMs, 2),
          reason: '$kind 规则表写的是 ${GameSfx.durationMsOf(kind)}ms，'
              '素材实际是 ${actualMs}ms');
    }
  });

  test('最小间隔必须大于音效时长（否则重触发会把上一声拦腰截断）', () {
    // 每类音效只有一个常驻播放器，新的会 seek(0) 打断旧的，所以「不截断」
    // 完全靠 minGapMs 兜住。变调最慢到 0.92 倍速，实际播放时长要按 1/0.92 放大。
    const double slowest = 0.92;
    for (final SfxKind kind in SfxKind.values) {
      final double longestMs = GameSfx.durationMsOf(kind) / slowest;
      expect(GameSfx.minGapMsOf(kind).toDouble(), greaterThanOrEqualTo(longestMs),
          reason: '$kind 间隔 ${GameSfx.minGapMsOf(kind)}ms '
              '小于最慢变调下的时长 ${longestMs.toStringAsFixed(0)}ms，会被截断');
    }
  });
}
