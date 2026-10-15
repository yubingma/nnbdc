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
}
