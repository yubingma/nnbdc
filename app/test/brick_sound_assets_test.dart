import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 消砖块音效资源契约测试：
/// 代码里引用的每一个音效文件都必须真实存在，且所在目录已在 pubspec 里声明。
/// （之前 correct.mp3 就是个不存在的文件，导致答对时静默无声。）
void main() {
  test('消砖块引用的音效资源存在且已声明', () {
    final source = File('lib/page/brick.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    final refs = RegExp(r"'([^']+\.(?:wav|mp3))'")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();
    expect(refs, isNotEmpty, reason: '必须至少引用一个音效');

    for (final name in refs) {
      expect(
        File('assets/audio/$name').existsSync(),
        true,
        reason: '音效文件不存在: assets/audio/$name',
      );
    }

    // pubspec 的 assets 声明不递归，子目录必须单独声明
    expect(pubspec, contains('assets/audio/'), reason: 'assets/audio/ 必须声明');
    expect(pubspec, contains('assets/audio/monster/'), reason: 'monster 子目录必须单独声明');
  });
}
