import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/widget/data_missing_guide.dart';
import 'package:provider/provider.dart';

/// 「通用释义缺失」发生时，用户必须看到可执行的出路，而不是一个必然再次失败的重试按钮。
void main() {
  Future<void> pumpGuide(
    WidgetTester tester, {
    String? wordSpell,
    VoidCallback? onRetry,
    VoidCallback? onBack,
  }) {
    return tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DarkMode(),
        child: MaterialApp(
          home: Scaffold(
            body: MissingMeaningGuide(
              wordSpell: wordSpell,
              onRetry: onRetry,
              onBack: onBack,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('引导面板给出「修复数据」与「清空本地数据重新同步」两条出路', (tester) async {
    await pumpGuide(tester, wordSpell: 'apple', onRetry: () {});

    expect(find.text('本机缺少这个词的释义'), findsOneWidget);
    expect(find.textContaining('apple'), findsOneWidget);
    expect(find.text('修复数据（数据健康检查）'), findsOneWidget);
    expect(find.text('清空本地数据重新同步'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('取不到单词拼写时不显示具体单词，也不虚构一个', (tester) async {
    await pumpGuide(tester);

    expect(find.text('本机缺少这个词的释义'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.text('返回'), findsNothing);
  });

  testWidgets('页面传了返回动作时才显示「返回」', (tester) async {
    await pumpGuide(tester, wordSpell: 'apple', onBack: () {});

    expect(find.text('返回'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });
}
