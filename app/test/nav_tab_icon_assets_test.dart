import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/model/nav_tab_config.dart';

/// 底栏图标的资源契约。
///
/// 图标从 Material 图标字体换成了 Lucide 的 SVG 资源（`assets/images/nav/`），
/// 于是「路径写错」和「目录没声明」这两件事都变成了只在真机运行时才报
/// 「Unable to load asset」的静默故障——编译、静态检查、甚至读文件系统都不出声。
/// 这几条断言就是为了拦住它，顺带钉住「五枚图标同属一套」这件事：
/// 原先混用 Material 的 filled 与 rounded 两套字形，墨迹覆盖率从 16% 到 45%
/// 不等，并排放在底栏里大小肉眼可见地不齐。
void main() {
  const assetDir = 'assets/images/nav/';

  /// 收纳菜单里「随身听」用的图标，与底栏同一套。
  const extraIcons = ['${assetDir}headphones.svg'];

  test('pubspec 声明了 assets/images/nav/（否则真机整目录不打包）', () {
    // Flutter 的资源目录声明只递归一层：`assets/images/` 覆盖它直接包含的文件，
    // 以及「一层子目录里直接包含的文件」。`images/nav/` 属于第二层子目录，
    // 不单独声明会被整个静默跳过。
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec.contains('- $assetDir'),
      isTrue,
      reason: 'pubspec.yaml 的 assets 段缺少 `- $assetDir`，底栏图标不会被打进包',
    );
  });

  test('每个底栏 Tab 的图标文件都存在', () {
    for (final tab in NavTabKey.values) {
      expect(File(tab.icon).existsSync(), isTrue, reason: '${tab.label} 缺少图标 ${tab.icon}');
    }
  });

  test('nav 目录里的图标与代码引用一一对应，不留孤儿文件', () {
    final declared = {
      ...NavTabKey.values.map((tab) => tab.icon),
      ...extraIcons,
    };
    final onDisk = Directory(assetDir)
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('.svg'))
        .toSet();
    expect(onDisk, declared, reason: 'nav 目录的文件必须与代码引用一一对应');
  });

  test('五枚图标同属一套：24 网格、2px 圆头笔宽', () {
    // 统一性全靠这几个属性撑着。混进一个别的网格或多粗/多细的笔画，
    // 底栏又会回到「大小不一致」的老样子。
    for (final tab in NavTabKey.values) {
      final svg = File(tab.icon).readAsStringSync();
      expect(svg.contains('viewBox="0 0 24 24"'), isTrue, reason: '${tab.label} 不是 24 网格：${tab.icon}');
      expect(svg.contains('stroke-width="2"'), isTrue, reason: '${tab.label} 笔宽不是 2：${tab.icon}');
      expect(svg.contains('stroke-linecap="round"'), isTrue, reason: '${tab.label} 不是圆头笔：${tab.icon}');
    }
  });
}
