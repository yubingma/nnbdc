import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nnbdc/main.dart' as app;

/// 先探一次路：确认「在真机上用 flutter test 驱动真实 App」这条路走得通、耗时多少。
/// 只做到「进入答题卡片」为止，不答题。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('探路：进入答题卡片', (tester) async {
    final watch = Stopwatch()..start();
    app.main();
    debugPrint('【探路】app.main() 已调用');

    final startBtn = find.bySemanticsIdentifier('e2e_home_start');
    final extraBtn = find.bySemanticsIdentifier('e2e_home_extra');
    await _waitFor(tester, () {
      return startBtn.evaluate().isNotEmpty || extraBtn.evaluate().isNotEmpty;
    }, label: '首页出现开始/继续学习', timeout: const Duration(seconds: 120));
    debugPrint('【探路】首页就绪，耗时 ${watch.elapsedMilliseconds}ms');

    await tester.tap(
        startBtn.evaluate().isNotEmpty ? startBtn.first : extraBtn.first);
    await _sleep(tester, const Duration(milliseconds: 600));

    final confirm = find.text('马上开始');
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm.first);
      await _sleep(tester, const Duration(milliseconds: 600));
    }

    // 新手语音引导蒙层
    final guide = find.textContaining('你说，我来听');
    if (guide.evaluate().isNotEmpty) {
      final guideBtn = find.text('开始学习');
      if (guideBtn.evaluate().isNotEmpty) {
        await tester.tap(guideBtn.last);
        await _sleep(tester, const Duration(milliseconds: 500));
      }
    }

    final option = find.bySemanticsIdentifier('e2e_study_option_0');
    await _waitFor(tester, () => option.evaluate().isNotEmpty,
        label: '答题卡片出现选项', timeout: const Duration(seconds: 60));

    final header = _headerText(tester);
    debugPrint('【探路】已进入答题卡片：$header，总耗时 ${watch.elapsedMilliseconds}ms');
    expect(header.contains('/'), isTrue, reason: '卡片顶部应有 n/N 进度');
  });
}

String _headerText(WidgetTester tester) {
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final data = widget.data ?? '';
    if (data.contains('组') && data.contains('/')) return data.replaceAll('\n', ' ');
  }
  return '';
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready, {
  required String label,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 120));
    if (ready()) return;
  }
  fail('等待超时：$label');
}

Future<void> _sleep(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}
