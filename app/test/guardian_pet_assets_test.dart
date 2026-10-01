import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/widget/guardian_pet.dart';

/// 守护兽组件的资源契约。
///
/// 这几条断言都来自真实事故，不是假想：
///   - 代码把情绪图写成 `assets/images/pet/mood_xxx.png`，而文件实际在 `moods/` 下，
///     编译期毫无提示，只有真机跑到这一屏才刷出一片「Unable to load asset」；
///   - 素材曾以 1116px 高度随包发布，而显示高度只有 116dp，白白占了 9 倍分辨率；
///   - 压缩脚本一度把透明区域压成实色，整只宠物破图，而编译与运行都不报错。
void main() {
  const assetDir = 'assets/images/pet';
  /// 完成页里宠物的显示高度（逻辑像素）。
  const displayHeight = 116;
  /// 素材目标高度 = 显示高度的 3 倍（3 倍屏下每个物理像素都有对应像素）。
  const targetHeight = displayHeight * 3;

  List<File> pngsIn(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.png'))
      .toList();

  Future<ui.Image> decode(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(Uint8List.view(bytes.buffer));
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// 统计透明像素数：把图渲染成 RGBA 字节流后逐像素看 alpha。
  Future<int> countTransparentPixels(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = data!.buffer.asUint8List();
    var transparent = 0;
    for (var i = 3; i < pixels.length; i += 4) {
      if (pixels[i] < 8) transparent++;
    }
    return transparent;
  }

  test('pubspec 声明了 pet 的两个子目录（否则真机整目录不打包）', () {
    // Flutter 的资源目录声明只递归一层：`assets/images/` 覆盖它直接包含的文件，以及
    // 「一层子目录里直接包含的文件」。`images/pet/moods/` 属于第二层子目录，不单独声明
    // 会被整个静默跳过——编译不报错、测试读文件系统也照样通过，只有真机运行才刷
    // 「Unable to load asset」。这条断言就是为了拦住它。
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final dir in ['assets/images/pet/moods/', 'assets/images/pet/layers/']) {
      expect(
        pubspec.contains('- $dir'),
        isTrue,
        reason: 'pubspec.yaml 的 assets 段缺少 `- $dir`，该目录下的图不会被打进包',
      );
    }
  });

  test('五个情绪图都在 assets/images/pet/moods/ 下存在', () {
    for (final mood in PetMood.values) {
      final path = '$assetDir/moods/${mood.assetName}.png';
      expect(File(path).existsSync(), isTrue, reason: '缺少情绪图 $path');
    }
  });

  test('三层动画素材都在 assets/images/pet/layers/ 下存在', () {
    const layers = [
      'guardian_gel_正面_身体层.png',
      'guardian_gel_正面_眼睛层.png',
      'guardian_gel_正面_光核层.png',
    ];
    for (final layer in layers) {
      expect(File('$assetDir/layers/$layer').existsSync(), isTrue, reason: '缺少分层素材 $layer');
    }
  });

  test('资源目录里没有多余的情绪图（改名后不留孤儿文件）', () {
    final declared = PetMood.values.map((m) => '${m.assetName}.png').toSet();
    final onDisk = pngsIn('$assetDir/moods').map((f) => f.uri.pathSegments.last).toSet();
    expect(onDisk, declared, reason: 'moods 目录的文件必须与 PetMood 枚举一一对应');
  });

  test('所有宠物素材等高，且不超过显示高度的 3 倍（防止再塞回 1116px 大图）', () async {
    final pngs = pngsIn(assetDir);
    expect(pngs, isNotEmpty);
    final heights = <int>{};
    for (final file in pngs) {
      final image = await decode(file);
      expect(
        image.height,
        lessThanOrEqualTo(targetHeight),
        reason: '${file.path} 高 ${image.height}px，超过显示高度 3 倍（$targetHeight）；'
            '应执行 tools/pet_assets/quantize_assets.py 重新压缩',
      );
      heights.add(image.height);
    }
    expect(heights.length, 1, reason: '所有图必须等高，否则叠层会错位');
  });

  test('每张图都保留透明区域（防止压缩把透明压成实色）', () async {
    for (final file in pngsIn(assetDir)) {
      final transparent = await countTransparentPixels(await decode(file));
      expect(
        transparent,
        greaterThan(0),
        reason: '${file.path} 没有任何透明像素——压缩脚本很可能把 alpha 压丢了',
      );
    }
  });
}
