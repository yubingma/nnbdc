import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/modes/mode_components.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/word_util.dart';

/// 阶段复习（本组小结）里错词的着色口径：
/// - 测评就没答对 → 红（与「新词答错/旧词答错」轨道同一判据）；
/// - 测评答对、后来巩固环节又答错 → 次级警示琥珀；
/// - 其余 → 正常字色。
///
/// 用户反馈：测评答对、在答对组的汉译英里又点了「不认识」，希望阶段复习里也能看出来。
void main() {
  Future<Color?> pumpSpellColor(
    WidgetTester tester, {
    required bool isWrongToday,
    bool isWrongLaterToday = false,
  }) async {
    final wrapper = WordWrapper(WordVo.c2('apple'), null)
      ..isWrongToday = isWrongToday
      ..isWrongLaterToday = isWrongLaterToday;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModeComponents.buildWordHeader(wrapper, false, false),
        ),
      ),
    );
    await tester.pump();
    return tester.widget<Text>(find.text('apple')).style?.color;
  }

  testWidgets('阶段复习：测评答错的词标红', (tester) async {
    expect(await pumpSpellColor(tester, isWrongToday: true),
        FsrsRating.again.colorWithDark(false));
  });

  testWidgets('阶段复习：测评答对、后来巩固又答错的词标次级琥珀色', (tester) async {
    expect(await pumpSpellColor(tester, isWrongToday: false, isWrongLaterToday: true),
        FsrsRating.hard.colorWithDark(false));
  });

  testWidgets('阶段复习：没答错的词保持正常字色', (tester) async {
    final color = await pumpSpellColor(tester, isWrongToday: false);
    expect(color, isNot(FsrsRating.again.colorWithDark(false)));
    expect(color, isNot(FsrsRating.hard.colorWithDark(false)));
  });
}
