import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/level_path_page.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// 真机宽度下的布局回归：成长之路页曾在 360/390dp 上横向溢出
/// (既有测试用的是测试默认的 800dp 宽面, 完全覆盖不到手机宽度, 因此漏掉了)。
void main() {
  Future<void> renderAt(WidgetTester tester, double width, int level, int words) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final darkMode = DarkMode();
    darkMode.setThemeStyle(AppThemeStyle.emerald);
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: darkMode,
        child: MaterialApp(
          home: LevelPathPage(currentLevel: level, masteredWords: words),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // 覆盖: 最窄在售机型 / 主流宽度 / 名字最长的段位 / 最高段位(无下一级) / 未掌握词数(不传)
  const widths = [320.0, 360.0, 390.0, 430.0];
  const cases = [
    (0, 0), // 毛毛虫
    (3, 60), // 皮皮虾, 短名
    (14, 4000), // 长颈鹿, 3 字名 + 当前段位徽章(体量重排后为 L14)
    (17, 20000), // 龙, 最高段位
  ];

  for (final width in widths) {
    for (final (level, words) in cases) {
      testWidgets('宽度 ${width}dp / 段位 $level 不横向溢出', (tester) async {
        await renderAt(tester, width, level, words);
        final error = tester.takeException();
        expect(error, isNull, reason: '${width}dp / 段位 $level 出现布局异常: $error');
      });
    }
  }

  testWidgets('未传入已掌握词数时也不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final darkMode = DarkMode();
    darkMode.setThemeStyle(AppThemeStyle.emerald);
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: darkMode,
        child: const MaterialApp(home: LevelPathPage(currentLevel: 5)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
