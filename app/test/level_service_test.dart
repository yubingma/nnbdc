import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/services/dialog_service.dart';
import 'package:nnbdc/services/level_service.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    final darkMode = DarkMode();
    darkMode.setThemeStyle(AppThemeStyle.emerald);
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: darkMode,
        child: MaterialApp(
          navigatorKey: DialogService.navigatorKey,
          home: const Scaffold(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('答题中不打断用户, 学习结束后补办晋升仪式', (tester) async {
    await pumpApp(tester);

    LevelService().enterStudy();
    // 毛毛虫(0-7) -> 蜗牛(8-19)
    await LevelService().checkPromotion(oldWordCount: 7, newWordCount: 8);
    await tester.pumpAndSettle();
    expect(find.text('段 位 晋 升'), findsNothing);

    LevelService().leaveStudy();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('段 位 晋 升'), findsOneWidget);
    expect(find.text('蜗牛'), findsOneWidget);

    await tester.tap(find.text('开心收下'));
    await tester.pumpAndSettle();
  });

  testWidgets('非答题状态下跨段立即举行仪式', (tester) async {
    await pumpApp(tester);
    LevelService().leaveStudy();

    // 蜗牛(8-19) -> 皮皮虾(20-44)
    await LevelService().checkPromotion(oldWordCount: 19, newWordCount: 20);
    await tester.pumpAndSettle();
    expect(find.text('段 位 晋 升'), findsOneWidget);
    expect(find.text('皮皮虾'), findsOneWidget);

    await tester.tap(find.text('开心收下'));
    await tester.pumpAndSettle();
  });

  testWidgets('段内增长与词数下降都不举行仪式', (tester) async {
    await pumpApp(tester);
    LevelService().leaveStudy();

    // 同在皮皮虾区间内
    await LevelService().checkPromotion(oldWordCount: 25, newWordCount: 30);
    // 词数下降
    await LevelService().checkPromotion(oldWordCount: 300, newWordCount: 20);
    await tester.pumpAndSettle();
    expect(find.text('段 位 晋 升'), findsNothing);
  });
}
