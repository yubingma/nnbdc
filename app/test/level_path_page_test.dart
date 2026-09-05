import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/level_path_page.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('LevelPathPage renders correctly with back button, header, and timeline nodes', (tester) async {
    final darkMode = DarkMode();
    darkMode.setThemeStyle(AppThemeStyle.aurora);

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: darkMode,
        child: const MaterialApp(
          home: LevelPathPage(
            currentLevel: 1,
            masteredWords: 120,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 验证标题和返回按钮
    expect(find.text('成长之路'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

    // 2. 验证顶部概览卡片
    expect(find.text('皮皮虾'), findsWidgets);
    expect(find.text('已掌握词汇'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('当前段位'), findsOneWidget);

    // 3. 验证未达成等级有锁图标
    expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
  });
}
