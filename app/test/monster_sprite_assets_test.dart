import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/widget/monster_sprite.dart';

/// 小馋怪走路动画的资源契约。
///
/// 这几条断言都来自真实事故，不是假想：
///   - 2026-10-14 新增该资源目录时只加了 `assets/images/`，
///     构建产物 `build/flutter_assets/assets/images/` 下**就是没有 monster 这一项**，
///     而编译、静态检查、单元测试全都毫无提示（`assets/` 声明**不递归**子目录）；
///   - 素材是 1280×1280 的抠底大图，13 张就是 8MB 量级，而手机上一只怪只显示约 160dp；
///   - 各帧若不等高、脚底不在同一条线上，走路会一跳一跳、脚会浮空。
void main() {
  const assetDir = 'assets/images/bridge';

  List<File> assetsIn(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.toLowerCase().endsWith('.png') ||
          f.path.toLowerCase().endsWith('.jpg'))
      .toList();

  Future<ui.Image> decode(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(Uint8List.view(bytes.buffer));
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<int> countTransparentPixels(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = data!.buffer.asUint8List();
    var transparent = 0;
    for (var i = 3; i < pixels.length; i += 4) {
      if (pixels[i] < 8) transparent++;
    }
    return transparent;
  }

  /// 把整段动画从头放到尾，收集过程中真正引用过的所有资源名。
  ///
  /// 比在测试里手抄一份清单可靠：清单一旦和代码脱节，这里立刻会红。
  Future<Set<String>> referencedAssets(WidgetTester tester,
      {required bool includeBackdrop}) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 360, height: 640, child: MonsterSprite(loop: false)),
      ),
    ));
    final seen = <String>{};
    void collect() {
      for (final Image img in tester.widgetList<Image>(find.byType(Image))) {
        final ImageProvider provider = img.image;
        if (provider is AssetImage) {
          if (!includeBackdrop && provider.assetName.endsWith('bg_bridge.jpg')) {
            continue;
          }
          seen.add(provider.assetName);
        }
      }
    }

    collect();
    // 全程 8.80 秒，每 40ms 采一次，足够覆盖 8 帧的走路循环与各姿势切换
    for (var i = 0; i < 220; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      collect();
    }
    return seen;
  }

  test('pubspec 显式声明了 assets/images/bridge/（否则整目录不进包）', () {
    // `assets/` 的资源声明**不递归**：声明 `assets/images/` 只覆盖它直接包含的文件，
    // 任何子目录都必须各自单独声明。漏了不会报错，只有真机跑到这一屏才刷
    // 「Unable to load asset」。本目录正是这么被漏掉过一次。
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec.contains('- assets/images/bridge/'),
      isTrue,
      reason: 'pubspec.yaml 的 assets 段缺少 `- assets/images/bridge/`，整目录不会被打进包',
    );
  });

  testWidgets('动画全程引用到的每一张图都真实存在', (tester) async {
    final referenced = await referencedAssets(tester, includeBackdrop: true);
    expect(referenced, isNotEmpty, reason: '整段动画没有引用任何资源，组件多半没渲染出来');
    for (final name in referenced) {
      expect(File(name).existsSync(), isTrue, reason: '代码引用了 $name，但文件不存在');
    }
  });

  testWidgets('资源目录里没有孤儿文件（每张图都被动画真正用到）', (tester) async {
    final referenced = await referencedAssets(tester, includeBackdrop: true);
    final onDisk = assetsIn(assetDir)
        .map((f) => f.path)
        .where((p) => !p.endsWith('.DS_Store'))
        .toSet();
    expect(onDisk, referenced,
        reason: '磁盘上的图必须与动画实际引用的图一一对应，改名或换帧后不能留下孤儿文件');
  });

  testWidgets('整段动画会依次走到正面走路、瘪嘴、哭、背面逃跑四种姿势', (tester) async {
    final referenced = await referencedAssets(tester, includeBackdrop: false);
    bool has(String prefix) => referenced.any((n) => n.split('/').last.startsWith(prefix));
    expect(has('front_'), isTrue, reason: '缺少正面走路帧');
    expect(has('pout'), isTrue, reason: '缺少被打中的瘪嘴帧');
    expect(has('cry'), isTrue, reason: '缺少哭脸帧');
    expect(has('back_'), isTrue, reason: '缺少背面逃跑帧');
  });

  test('所有帧共用同一块画布与同一条脚底线，且不超过显示高度的 3 倍', () async {
    final pngs = assetsIn(assetDir).where((f) => f.path.endsWith('.png')).toList();
    expect(pngs, isNotEmpty);
    final sizes = <String>{};
    final feetYs = <int>{};
    for (final file in pngs) {
      final image = await decode(file);
      sizes.add('${image.width}x${image.height}');
      expect(image.height, lessThanOrEqualTo(540),
          reason: '${file.path} 高 ${image.height}px；手机上一只怪只显示约 160dp，'
              '应执行 tools/sprite_anim/pack_app_assets.py 重新压缩');

      // 脚底（不透明像素的最低一行）必须落在同一条线上，否则角色会一跳一跳
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = data!.buffer.asUint8List();
      var lowest = -1;
      for (var y = image.height - 1; y >= 0 && lowest < 0; y--) {
        for (var x = 0; x < image.width; x++) {
          if (pixels[(y * image.width + x) * 4 + 3] > 60) {
            lowest = y;
            break;
          }
        }
      }
      feetYs.add(lowest);
    }
    expect(sizes.length, 1,
        reason: '所有帧必须同画布，否则叠层与锚点会错位，实际为 $sizes');
    expect(feetYs.length, 1, reason: '所有帧的脚底必须在同一行，实际为 $feetYs');
  });

  test('每张帧都保留透明区域（防止压缩把 alpha 压丢）', () async {
    for (final file in assetsIn(assetDir).where((f) => f.path.endsWith('.png'))) {
      final transparent = await countTransparentPixels(await decode(file));
      expect(transparent, greaterThan(0),
          reason: '${file.path} 没有任何透明像素——压缩脚本很可能把 alpha 压丢了');
    }
  });

  test('整套素材不超过 400KB（防止再塞回未压缩的大图）', () {
    final total = assetsIn(assetDir).fold<int>(0, (sum, f) => sum + f.lengthSync());
    expect(total, lessThan(400 * 1024),
        reason: '整套素材 ${(total / 1024).round()}KB，超出预算；'
            '应执行 tools/sprite_anim/pack_app_assets.py 重新压缩');
  });
}
