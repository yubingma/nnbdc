import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/word_util.dart';

/// 「本轮开口结论」是背单词页与词表页共用的同一句话：
/// 没有它，答错与"程序卡死"在界面上完全一样。
void main() {
  group('本轮开口结论的文案', () {
    test('暂无结论时不展示', () {
      expect(asrRoundVerdictText(null), isNull);
    });

    test('什么都没听到时说"没听清，再说一遍"', () {
      expect(asrRoundVerdictText(''), '没听清，再说一遍');
    });

    test('听到了但它不对时，回显原话', () {
      expect(asrRoundVerdictText('露水'), '听到的是「露水」，不对');
    });
  });

  group('词表页行内结论', () {
    Widget wrap(Widget child) =>
        MaterialApp(home: Scaffold(body: Center(child: child)));

    testWidgets('判错时把回显显示成醒目的一行小字', (tester) async {
      await tester.pumpWidget(wrap(buildAsrRoundVerdict('露水')));

      expect(find.text('听到的是「露水」，不对'), findsOneWidget);

      final textWidget = tester.widget<Text>(find.text('听到的是「露水」，不对'));
      expect(textWidget.style?.color, Colors.orange);
      expect(textWidget.style?.fontSize, 10);
    });

    testWidgets('没听清时显示"没听清，再说一遍"', (tester) async {
      await tester.pumpWidget(wrap(buildAsrRoundVerdict('')));

      expect(find.text('没听清，再说一遍'), findsOneWidget);
    });

    testWidgets('暂无结论时不占位：行高不变', (tester) async {
      await tester.pumpWidget(wrap(buildAsrRoundVerdict(null)));

      expect(find.byType(Text), findsNothing);
    });
  });
}
