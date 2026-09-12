import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/bdc/widgets/study_guide_overlay.dart';
import 'package:nnbdc/state.dart';
import 'package:provider/provider.dart';

void main() {
  final overlayKey = GlobalKey();
  final targetKey = GlobalKey();

  Future<void> pumpGuide(
    WidgetTester tester, {
    required VoidCallback onFinish,
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
                Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(key: targetKey, width: 200, height: 80),
                ),
                Positioned.fill(
                  child: StudyGuideOverlay(
                    overlayKey: overlayKey,
                    onFinish: onFinish,
                    steps: [
                      StudyGuideStep(
                        targetKey: targetKey,
                        title: '第一步标题',
                        text: '第一步说明',
                      ),
                      StudyGuideStep(
                        targetKey: targetKey,
                        title: '第二步标题',
                        text: '第二步说明',
                      ),
                      StudyGuideStep(
                        targetKey: targetKey,
                        title: '第三步标题',
                        text: '第三步说明',
                      ),
                    ],
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

  testWidgets('逐屏推进，最后一步完成回调；中途可跳过', (tester) async {
    int finished = 0;
    await pumpGuide(tester, onFinish: () => finished++);

    expect(find.text('第一步标题'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('第二步标题'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('第三步标题'), findsOneWidget);
    // 最后一步不再提供"跳过"，动作变为"开始学习"
    expect(find.text('跳过'), findsNothing);
    expect(find.text('开始学习'), findsOneWidget);

    await tester.tap(find.text('开始学习'));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('跳过直接结束引导', (tester) async {
    int finished = 0;
    await pumpGuide(tester, onFinish: () => finished++);

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });
}
