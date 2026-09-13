import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/widget/learning_history_dialog.dart';
import 'package:provider/provider.dart';

/// 记忆历史弹窗：毛玻璃手感（模糊层 + 足够实的底色）与基本交互回归。
void main() {
  LearningLog log(int rating, int scheduledDays, DateTime time) => LearningLog(
        id: 'log_${rating}_$scheduledDays',
        userId: 'u_1',
        wordId: 'w_1',
        rating: rating,
        stability: 1.0,
        difficulty: 5.0,
        elapsedDays: 0,
        scheduledDays: scheduledDays,
        createTime: time,
        updateTime: time,
      );

  Future<void> pumpHost(WidgetTester tester) async {
    final darkMode = DarkMode();
    darkMode.setThemeStyle(AppThemeStyle.emerald);
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: darkMode,
        child: const MaterialApp(home: Scaffold()),
      ),
    );
  }

  /// 弹窗底色（BackdropFilter 内的第一个 Container）。
  Container cardOf(WidgetTester tester) => tester.widget<Container>(
        find
            .descendant(
                of: find.byType(BackdropFilter), matching: find.byType(Container))
            .first,
      );

  testWidgets('记忆历史弹窗：磨砂底 + 记录列表 + 关闭', (tester) async {
    await pumpHost(tester);

    showLearningHistoryDialog(
      tester.element(find.byType(Scaffold)),
      history: [
        log(FsrsRating.good.value, 3, DateTime(2026, 5, 20, 8, 30)),
        log(FsrsRating.again.value, 1, DateTime(2026, 5, 19, 21, 5)),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('记忆历史'), findsOneWidget);
    expect(find.text('良好'), findsOneWidget);
    expect(find.text('忘记'), findsOneWidget);
    expect(find.text('2026-05-20 08:30'), findsOneWidget);

    // 毛玻璃：必须有模糊层，且底色要足够实（原来的 cardBg 50% 会导致文字糊在一起）
    expect(find.byType(BackdropFilter), findsOneWidget,
        reason: '弹窗必须有毛玻璃模糊层');
    expect(cardOf(tester).color!.a, greaterThan(0.8),
        reason: '底色不透明度要明显高于 cardBg(0.5)，否则底层文字透上来会看不清');

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('记忆历史'), findsNothing);
  });

  testWidgets('记忆历史弹窗：无记录时显示占位文案', (tester) async {
    await pumpHost(tester);

    showLearningHistoryDialog(
      tester.element(find.byType(Scaffold)),
      history: const [],
    );
    await tester.pumpAndSettle();

    expect(find.text('记忆历史'), findsOneWidget);
    expect(find.text('暂无记忆历史'), findsOneWidget);
  });

  testWidgets('记忆历史弹窗：记录很多时列表内部滚动，不撑破弹窗', (tester) async {
    await pumpHost(tester);

    showLearningHistoryDialog(
      tester.element(find.byType(Scaffold)),
      history: List.generate(
          30, (i) => log(FsrsRating.good.value, i + 1, DateTime(2026, 5, 20, 8, 30))),
    );
    await tester.pumpAndSettle();

    expect(find.text('记忆历史'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget,
        reason: '列表再长也不能把标题/关闭按钮挤出弹窗');
  });
}
