import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/widget/guardian_pet.dart';

/// 守护兽组件的资源必须在 `app/assets/images/pet/` 下真实存在。
///
/// 这条断言来自一次真实事故：代码把情绪图写成 `assets/images/pet/mood_xxx.png`，
/// 而文件实际在 `assets/images/pet/moods/` 下，编译期毫无提示，只有真机运行到这一屏
/// 才会刷出一片「Unable to load asset」。资源路径错了必须在测试阶段就红。
void main() {
  const assetDir = 'assets/images/pet';

  test('五个情绪图都在 assets/images/pet/moods/ 下存在', () {
    for (final mood in PetMood.values) {
      final path = '$assetDir/moods/${mood.assetName}.png';
      expect(
        File(path).existsSync(),
        isTrue,
        reason: '缺少情绪图 $path（PetMood.${mood.name} 指向的文件不存在）',
      );
    }
  });

  test('三层动画素材都在 assets/images/pet/layers/ 下存在', () {
    const layers = [
      'guardian_gel_正面_身体层.png',
      'guardian_gel_正面_眼睛层.png',
      'guardian_gel_正面_光核层.png',
    ];
    for (final layer in layers) {
      final path = '$assetDir/layers/$layer';
      expect(File(path).existsSync(), isTrue, reason: '缺少动画分层素材 $path');
    }
  });

  test('资源目录里没有多余的情绪图（防止改名后留下孤儿文件）', () {
    final declared = PetMood.values.map((m) => '${m.assetName}.png').toSet();
    final onDisk = Directory('$assetDir/moods')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.png'))
        .toSet();
    expect(onDisk, declared, reason: 'moods 目录里的文件与 PetMood 枚举必须一一对应');
  });
}
