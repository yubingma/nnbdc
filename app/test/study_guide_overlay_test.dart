import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/page/bdc/widgets/study_guide_overlay.dart';
import 'package:nnbdc/state.dart';
import 'package:provider/provider.dart';

void main() {
  final overlayKey = GlobalKey();
  final targetKey = GlobalKey();

  Future<void> pumpGuide(
    WidgetTester tester, {
    required VoidCallback onFinish,
    bool withTarget = true,
  }) async {
    // 手机尺寸画布：引导卡位置依赖真实可用高度
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (withTarget)
                  Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(key: targetKey, width: 200, height: 80),
                  ),
                Positioned.fill(
                  child: StudyGuideOverlay(
                    overlayKey: overlayKey,
                    targetKey: targetKey,
                    title: '你说，我来听',
                    text: '看着英文直接说出中文释义',
                    onFinish: onFinish,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // 等引导完成首帧测量与重建
    await tester.pumpAndSettle();
  }

  testWidgets('只讲「你说，我来听」一个点：点「开始学习」结束引导', (tester) async {
    int finished = 0;
    await pumpGuide(tester, onFinish: () => finished++);

    expect(find.text('你说，我来听'), findsOneWidget);
    expect(find.text('看着英文直接说出中文释义'), findsOneWidget);
    // 单点引导不再有「跳过 / 下一步」这类多步指令
    expect(find.text('跳过'), findsNothing);
    expect(find.text('下一步'), findsNothing);

    await tester.tap(find.text('开始学习'));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('高亮目标未挂载时退化为居中说明卡，点击仍可结束', (tester) async {
    int finished = 0;
    await pumpGuide(tester, onFinish: () => finished++, withTarget: false);

    expect(find.text('你说，我来听'), findsOneWidget);

    await tester.tap(find.text('开始学习'));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  group('引导正文随当前学习环节变化', () {
    test('英译汉：说中文意思', () {
      expect(studyGuideTextFor(StudyStep.en2Ch), contains('中文意思'));
    });

    test('汉译英：说英文单词', () {
      expect(studyGuideTextFor(StudyStep.ch2En), contains('英文单词'));
    });

    test('例句环节：先按住说话', () {
      expect(studyGuideTextFor(StudyStep.enSentence2Ch), contains('按住说话'));
      expect(studyGuideTextFor(StudyStep.chSentence2En), contains('按住说话'));
    });

    test('任何环节的文案都不提"测评"', () {
      for (final step in StudyStep.values) {
        expect(studyGuideTextFor(step), isNot(contains('测评')),
            reason: '$step 的引导文案不应出现"测评"');
      }
    });
  });
}
