import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 对战页音效资源的落地检查。
///
/// 音效文件名写错时，编译、静态检查、单测全都不会报，只有真机上打到那一刻
/// 才发现没声音——所以这里直接按页面代码里引用到的文件名逐个核对文件是否存在。
void main() {
  group('对战页音效资源', () {
    test('页面代码引用的音效都真实存在，且音频目录已随包声明', () {
      final source = File('lib/page/russia.dart').readAsStringSync();
      final names = RegExp(r"play(?:SoundEffect|BlockingSound)\('([^']+)'")
          .allMatches(source)
          .map((match) => match.group(1)!)
          .toSet();

      expect(names, isNotEmpty, reason: '对战页应该引用了音效');

      for (final name in names) {
        final file = File('assets/audio/$name');
        expect(file.existsSync(), isTrue, reason: '代码引用的音效不存在: assets/audio/$name');
        expect(file.lengthSync(), greaterThan(0), reason: '音效是空文件: assets/audio/$name');
      }

      // assets/audio/ 只递归一层，音效必须直接躺在这一层，目录也必须声明过
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/audio/'), reason: 'pubspec 未声明音频目录，音效不会随包发布');
    });
  });
}
