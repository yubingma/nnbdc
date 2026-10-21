import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/main.dart' as app;
import 'package:nnbdc/page/bdc/bdc.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 在真机上用 flutter test 驱动真实 App 学完当天计划。
///
/// 前提：账号已登录、词书已导入、今日计划已设好（由 run_regression.py --prepare-only 完成）。
///
/// 判对错的真值不取 App 的 `correctAnswerIndex`（那等于拿被验证的东西去验证它自己），
/// 而是拿卡片上的单词拼写去 `meaning_items` 里查释义，再和屏幕上的选项文字比对。
///
/// 参数：`--dart-define=E2E_WORDS=3` 只答 3 个词就停（试跑用）；不传则学到出现完成打卡页。
const int _capWords = int.fromEnvironment('E2E_WORDS', defaultValue: 0);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('学完当天计划', (tester) async {
    final semantics = tester.ensureSemantics();
    final watch = Stopwatch()..start();
    app.main();

    // 1. 进学习页
    final startBtn = find.bySemanticsIdentifier('e2e_home_start');
    final extraBtn = find.bySemanticsIdentifier('e2e_home_extra');
    await _waitFor(tester, () {
      return startBtn.evaluate().isNotEmpty || extraBtn.evaluate().isNotEmpty;
    }, label: '首页出现开始/继续学习', timeout: const Duration(seconds: 120));
    debugPrint('【E2E】首页就绪 ${watch.elapsedMilliseconds}ms');

    await tester.tap(startBtn.evaluate().isNotEmpty ? startBtn.first : extraBtn.first);
    await _settle(tester);

    final confirm = find.text('马上开始');
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm.first);
      await _settle(tester);
    }

    // 2. 先关掉新手语音引导蒙层。它是模态的，会把底下答题卡片的语义树挡住，
    //    所以必须关在「等卡片」之前，否则会一直等不到卡片。
    await _dismissVoiceGuide(tester, waitForIt: true);
    await _waitFor(tester, () => find.bySemanticsIdentifier('e2e_study_dont_know').evaluate().isNotEmpty,
        label: '出现答题卡片', timeout: const Duration(seconds: 90));
    await _switchToChoice(tester);
    debugPrint('【E2E】答题卡片就绪 ${watch.elapsedMilliseconds}ms');

    // 3. 逐题作答，直到完成打卡页
    var answered = 0;
    for (var turn = 0; turn < 400; turn++) {
      if (find.bySemanticsIdentifier('e2e_finish_page').evaluate().isNotEmpty ||
          find.bySemanticsIdentifier('e2e_badge_claim').evaluate().isNotEmpty) {
        break;
      }
      if (_capWords > 0 && answered >= _capWords) {
        debugPrint('【E2E】已答 $answered 个词，按 E2E_WORDS 上限停下');
        semantics.dispose();
        return;
      }

      // 已作答、等下一词
      final nextWord = find.bySemanticsIdentifier('e2e_study_next_word');
      if (nextWord.evaluate().isNotEmpty) {
        await tester.tap(nextWord.first);
        await _settle(tester);
        continue;
      }
      // 单词详情页（答错后出现）
      final detailNext = find.bySemanticsIdentifier('e2e_detail_next_word');
      if (detailNext.evaluate().isNotEmpty) {
        await tester.tap(detailNext.first);
        await _settle(tester);
        continue;
      }
      final detail = find.bySemanticsIdentifier('e2e_word_detail');
      if (detail.evaluate().isNotEmpty) {
        final back = find.byType(BackButton);
        if (back.evaluate().isNotEmpty) {
          await tester.tap(back.first);
        } else {
          await tester.pageBack();
        }
        await _settle(tester);
        continue;
      }
      // 本组小结
      final nextGroup = find.bySemanticsIdentifier('e2e_study_next_group');
      if (nextGroup.evaluate().isNotEmpty) {
        await tester.tap(nextGroup.first);
        await _settle(tester);
        continue;
      }

      final options = _optionFinders();
      if (options.isEmpty) {
        final dontKnow = find.bySemanticsIdentifier('e2e_study_dont_know');
        if (dontKnow.evaluate().isNotEmpty) {
          await tester.tap(dontKnow.first);
          await _settle(tester);
          continue;
        }
        await _sleep(tester, const Duration(milliseconds: 350));
        continue;
      }

      final spell = _currentSpell(tester);
      final meanings = spell == null ? <String>[] : await _meaningsOf(spell);
      final picked = await _pickCorrect(tester, options, meanings);
      await tester.tap(options[picked].first);
      answered++;
      await _settle(tester);
    }

    // 4. 断言：到完成打卡页
    await _waitFor(tester,
        () => find.bySemanticsIdentifier('e2e_finish_page').evaluate().isNotEmpty ||
            find.bySemanticsIdentifier('e2e_badge_claim').evaluate().isNotEmpty,
        label: '完成打卡页出现', timeout: const Duration(seconds: 60));
    debugPrint('【E2E】学完当天计划，共答 $answered 个词，总耗时 ${watch.elapsedMilliseconds}ms');

    // 5. 断言：本地库真的写进了评分流水，且 FSRS 字段合法
    final rows = await MyDatabase.instance.customSelect(
      'SELECT rating, stability, difficulty, scheduled_days FROM learning_logs '
      'ORDER BY create_time DESC LIMIT 200',
    ).get();
    expect(rows, isNotEmpty, reason: '本地 learning_logs 应有用今天的评分流水');
    for (final row in rows) {
      final rating = row.read<int>('rating');
      expect(rating, inInclusiveRange(1, 4), reason: 'FSRS 评分必须在 1~4');
      expect(row.read<double>('stability'), greaterThan(0), reason: '稳定性必须大于 0');
      expect(row.read<int>('scheduled_days'), greaterThan(0), reason: '下次复习间隔必须大于 0');
    }
    debugPrint('【E2E】本地库审计通过，最近 ${rows.length} 条流水全部合法');
    semantics.dispose();
  });
}

List<Finder> _optionFinders() {
  final result = <Finder>[];
  for (var i = 0; i < 8; i++) {
    final finder = find.bySemanticsIdentifier('e2e_study_option_$i');
    if (finder.evaluate().isNotEmpty) result.add(finder);
  }
  return result;
}

/// 卡片顶部的英文单词：直接读当前答题状态里的 word，不碰 correctAnswerIndex。
String? _currentSpell(WidgetTester tester) {
  final page = find.byType(BdcPage);
  if (page.evaluate().isEmpty) return null;
  final container = ProviderScope.containerOf(tester.element(page.first));
  return container.read(bdcNotifierProvider).word?.spell;
}

Future<List<String>> _meaningsOf(String spell) async {
  final rows = await MyDatabase.instance.customSelect(
    'SELECT m.meaning FROM meaning_items m JOIN words w ON w.id = m.word_id '
    'WHERE w.spell = ?',
    variables: [Variable<String>(spell)],
  ).get();
  return rows.map((r) => r.read<String>('meaning')).toList();
}

/// 选命中释义最多且唯一的那个选项；判不出唯一答案就点第一个。
Future<int> _pickCorrect(WidgetTester tester, List<Finder> options, List<String> meanings) async {
  if (meanings.isEmpty) return 0;
  final scores = <int>[];
  for (final option in options) {
    final texts = find
        .descendant(of: option, matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .join(' ');
    scores.add(meanings.where((m) => m.isNotEmpty && texts.contains(m)).length);
  }
  final best = scores.reduce((a, b) => a > b ? a : b);
  if (best < 1) return 0;
  if (scores.where((s) => s == best).length > 1) return 0;
  return scores.indexOf(best);
}

Future<void> _switchToChoice(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    if (_optionFinders().isNotEmpty) return;
    final toggle = find.bySemanticsIdentifier('e2e_study_mode_switch');
    if (toggle.evaluate().isEmpty) break;
    await tester.tap(toggle.first);
    await _settle(tester);
  }
}

/// 关掉新手语音引导蒙层「你说，我来听」。
///
/// 两个坑：一是蒙层上的按钮文案虽然是「开始学习」，但可能是 RichText，
/// `find.text` 未必命中；二是它是模态的，弹着的时候底下卡片的语义树会被挡住，
/// 所以必须「先关它，再等卡片」。关不掉就报错，绝不带着它空转。
Future<void> _dismissVoiceGuide(WidgetTester tester, {bool waitForIt = false}) async {
  final deadline = DateTime.now().add(Duration(seconds: waitForIt ? 10 : 1));
  var attempts = 0;
  while (true) {
    final guide = find.textContaining('你说，我来听');
    if (guide.evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) return;
      await _sleep(tester, const Duration(milliseconds: 200));
      continue;
    }
    if (attempts++ >= 6) fail('语音引导蒙层关不掉，后续作答会被它挡住');
    final byText = find.textContaining('开始学习');
    if (byText.evaluate().isNotEmpty) {
      await tester.tap(byText.last);
    } else {
      await tester.tapAt(const Offset(40, 300));
    }
    await _settle(tester);
    if (find.textContaining('你说，我来听').evaluate().isEmpty) return;
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready, {
  required String label,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
  }
  fail('等待超时：$label');
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _sleep(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
