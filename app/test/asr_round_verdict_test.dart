import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/word_util.dart';

/// 「本轮开口」的反馈是背单词页与词表页共用的一套口径：
/// 一个 0~100 的匹配度数字，外加只在什么都没听清时的一句短提示。
/// 明确**不回显用户说的原话**——说一长句时那行字既放不下也读不清（线上反馈）。
void main() {
  group('匹配度数字', () {
    Widget wrap(Widget child) =>
        MaterialApp(home: Scaffold(body: Center(child: child)));

    testWidgets('还没有分数时不占位', (tester) async {
      await tester.pumpWidget(wrap(buildAsrMatchScore(null)));

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('0 分也要显示：说错了不等于没反应', (tester) async {
      await tester.pumpWidget(wrap(buildAsrMatchScore(0)));

      expect(find.text('匹配度 0'), findsOneWidget,
          reason: '一个字都不沾时，0 才是"系统听清了但完全不对"的证据');
    });

    testWidgets('分数用醒目的橙字显示', (tester) async {
      await tester.pumpWidget(wrap(buildAsrMatchScore(87)));

      final textWidget = tester.widget<Text>(find.text('匹配度 87'));
      expect(textWidget.style?.color, Colors.orange);
      expect(textWidget.maxLines, 1);
    });
  });

  group('没听清提示', () {
    test('文案固定一句短话，不做原话回显', () {
      expect(asrHeardNothingText, '没听清，再说一遍');
    });
  });
}
