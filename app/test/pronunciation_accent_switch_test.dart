import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/widget/pronunciation_accent_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    await Prefs.setPronunciationAccent('us');
  });

  group('发音口音切换与响应式通知测试', () {
    test('Prefs.togglePronunciationAccent 应在 us 与 uk 之间快速取反并通知', () async {
      expect(Prefs.pronunciationAccent, 'us');
      expect(Prefs.pronunciationAccentNotifier.value, 'us');

      // 切换为 uk
      final accent1 = await Prefs.togglePronunciationAccent();
      expect(accent1, 'uk');
      expect(Prefs.pronunciationAccent, 'uk');
      expect(Prefs.pronunciationAccentNotifier.value, 'uk');

      // 再次切换为 us
      final accent2 = await Prefs.togglePronunciationAccent();
      expect(accent2, 'us');
      expect(Prefs.pronunciationAccent, 'us');
      expect(Prefs.pronunciationAccentNotifier.value, 'us');
    });

    test('Util.getWordPronounceWithAccent 应随口音切换返回对应口音音标和标签', () async {
      final word = WordVo.c2('schedule')
        ..americaPronounce = "ˈskedʒuːl"
        ..britishPronounce = "ˈʃedjuːl";

      // 初始为 us
      await Prefs.setPronunciationAccent('us');
      var pronInfo = Util.getWordPronounceWithAccent(word);
      expect(pronInfo.$1, "ˈskedʒuːl");
      expect(pronInfo.$2, '美');
      expect(pronInfo.$3, false);

      // 切换为 uk
      await Prefs.setPronunciationAccent('uk');
      pronInfo = Util.getWordPronounceWithAccent(word);
      expect(pronInfo.$1, "ˈʃedjuːl");
      expect(pronInfo.$2, '英');
      expect(pronInfo.$3, false);
    });

    test('对于无音标的复合短语（如 keyboard key），音标为空但口音小按钮标签仍能正确跟随偏好', () async {
      final phrase = WordVo.c2('keyboard key');
      // 此时 phrase 的 britishPronounce, americaPronounce, pronounce 均为 null/空

      await Prefs.setPronunciationAccent('us');
      var pronInfo = Util.getWordPronounceWithAccent(phrase);
      expect(pronInfo.$1, '');
      expect(pronInfo.$2, '美');
      expect(pronInfo.$3, false);

      await Prefs.setPronunciationAccent('uk');
      pronInfo = Util.getWordPronounceWithAccent(phrase);
      expect(pronInfo.$1, '');
      expect(pronInfo.$2, '英');
      expect(pronInfo.$3, false);
    });

    testWidgets('PronunciationAccentBadge 点击触发切换并调用 onSwitched 回调', (tester) async {
      String? switchedAccent;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PronunciationAccentBadge(
                label: '美',
                onSwitched: (newAccent) async {
                  switchedAccent = newAccent;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('美'), findsOneWidget);

      // 点击按钮
      await tester.tap(find.text('美'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // 验证已切换为 uk
      expect(switchedAccent, 'uk');
      expect(Prefs.pronunciationAccent, 'uk');
    });
  });
}
