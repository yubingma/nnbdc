import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/services/dialog_service.dart';
import 'package:nnbdc/services/level_service.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    final darkMode = DarkMode();
    darkMode.setThemeStyle(AppThemeStyle.emerald);
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: darkMode,
        child: ToastificationWrapper(
          child: MaterialApp(
            navigatorKey: DialogService.navigatorKey,
            home: const Scaffold(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('判定结果(不含 UI)', () {
    test('跨段返回 promotion', () async {
      // 毛毛虫(0-7) -> 蜗牛(8-19)
      final advance = await LevelService().checkProgress(oldWordCount: 7, newWordCount: 8);

      expect(advance, isNotNull);
      expect(advance!.isPromotion, isTrue);
      expect(advance.level.name, '蜗牛');
      expect(advance.stars, 1);
    });

    test('段内跨星级分位返回 starUp 及当前星数', () async {
      // 仓鼠 20-44(五等分点 25/30/35/40): 24 词是 1 星, 25 词进入 2 星
      final advance = await LevelService().checkProgress(oldWordCount: 24, newWordCount: 25);

      expect(advance, isNotNull);
      expect(advance!.isPromotion, isFalse);
      expect(advance.level.name, '仓鼠');
      expect(advance.stars, 2);
    });

    test('未跨星级分位返回 null', () async {
      // 25 -> 29 同为 2 星
      expect(await LevelService().checkProgress(oldWordCount: 25, newWordCount: 29), isNull);
    });

    test('词数下降返回 null', () async {
      expect(await LevelService().checkProgress(oldWordCount: 300, newWordCount: 20), isNull);
    });

    test('一次跨越多个段位只报最后到达的段位', () async {
      final advance = await LevelService().checkProgress(oldWordCount: 0, newWordCount: 130);

      expect(advance!.isPromotion, isTrue);
      expect(advance.level.name, '兔子');
    });
  });

  group('反馈时机', () {
    testWidgets('答题中不打断用户, 学习结束后补办晋升仪式', (tester) async {
      await pumpApp(tester);

      LevelService().enterStudy();
      await LevelService().checkProgress(oldWordCount: 7, newWordCount: 8);
      await tester.pumpAndSettle();
      expect(find.text('段 位 晋 升'), findsNothing);

      LevelService().leaveStudy();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('段 位 晋 升'), findsOneWidget);
      expect(find.text('蜗牛'), findsOneWidget);

      await tester.tap(find.text('开心收下'));
      await tester.pumpAndSettle();
    });

    testWidgets('非答题状态下跨段立即举行仪式', (tester) async {
      await pumpApp(tester);
      LevelService().leaveStudy();

      await LevelService().checkProgress(oldWordCount: 19, newWordCount: 20);
      await tester.pumpAndSettle();
      expect(find.text('段 位 晋 升'), findsOneWidget);
      expect(find.text('仓鼠'), findsOneWidget);

      await tester.tap(find.text('开心收下'));
      await tester.pumpAndSettle();
    });

    testWidgets('同一次学习中先升星后晋级, 只办晋级仪式一次', (tester) async {
      await pumpApp(tester);

      LevelService().enterStudy();
      final starUp = await LevelService().checkProgress(oldWordCount: 24, newWordCount: 25);
      final promotion = await LevelService().checkProgress(oldWordCount: 44, newWordCount: 45);
      expect(starUp!.isPromotion, isFalse);
      expect(promotion!.isPromotion, isTrue);

      LevelService().leaveStudy();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('段 位 晋 升'), findsOneWidget);
      expect(find.text('皮皮虾'), findsOneWidget);

      await tester.tap(find.text('开心收下'));
      await tester.pumpAndSettle();
      expect(find.text('段 位 晋 升'), findsNothing);
    });
  });
}
