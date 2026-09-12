import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/level_util.dart';
import 'package:nnbdc/widget/level_up_dialog.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('LevelUpDialog 展示晋升段位、台词与奖励', (tester) async {
    final darkMode = DarkMode();
    darkMode.setThemeStyle(AppThemeStyle.emerald);

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: darkMode,
        child: const MaterialApp(home: Scaffold()),
      ),
    );

    final level = LevelUtil.getTitle(3); // 仓鼠
    final closed = LevelUpDialog.show(
      tester.element(find.byType(Scaffold)),
      level: level,
      rewardBubbles: 90,
    );
    await tester.pumpAndSettle();

    expect(find.text('段 位 晋 升'), findsOneWidget);
    expect(find.text(level.name), findsOneWidget);
    expect(find.text('LV.${level.level}'), findsOneWidget);
    expect(find.text(level.icon), findsOneWidget);
    expect(find.text('晋升奖励 +90 魔法泡泡'), findsOneWidget);
    expect(find.text('开心收下'), findsOneWidget);
    expect(find.text('成长之路'), findsOneWidget);

    await tester.tap(find.text('开心收下'));
    await tester.pumpAndSettle();
    expect(find.text('段 位 晋 升'), findsNothing);
    await closed;
  });
}
