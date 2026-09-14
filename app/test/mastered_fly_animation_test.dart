import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/bdc/widgets/mastered_fly_animation.dart';

void main() {
  testWidgets('MasteredFlyAnimation - 正常播放且不抛出 ParentDataWidget 异常，并在完成时触发 onArrived',
      (WidgetTester tester) async {
    final startKey = GlobalKey();
    final targetKey = GlobalKey();
    bool arrivedCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 400,
                left: 100,
                child: SizedBox(
                  key: startKey,
                  width: 120,
                  height: 40,
                  child: const Text('apple'),
                ),
              ),
              Positioned(
                top: 60,
                right: 30,
                child: SizedBox(
                  key: targetKey,
                  width: 50,
                  height: 30,
                  child: const Text('掌握'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final context = tester.element(find.byType(Scaffold));

    // 触发飞行动画
    MasteredFlyAnimation.play(
      context: context,
      spell: 'apple',
      startKey: startKey,
      targetKey: targetKey,
      onArrived: () {
        arrivedCalled = true;
      },
    );

    // 第一帧：Overlay 已插入，检查飞行动画组件和文本已存在
    await tester.pump();
    expect(find.text('apple'), findsNWidgets(2)); // startKey 内原本的 + 飞行动画里的

    // 飞行中途（200ms）
    await tester.pump(const Duration(milliseconds: 200));
    expect(arrivedCalled, isFalse);

    // 飞行到达（650ms）
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // 验证完成回调已触发，Overlay 已经清理
    expect(arrivedCalled, isTrue);
    expect(find.text('apple'), findsOneWidget); // 仅剩页面内的原本一个
  });

  testWidgets('MasteredFlyAnimation - 传入 null 键时可自动降级为屏幕自适应坐标并平稳结束',
      (WidgetTester tester) async {
    bool arrivedCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Container(),
        ),
      ),
    );

    final context = tester.element(find.byType(Scaffold));

    MasteredFlyAnimation.play(
      context: context,
      spell: 'banana',
      startKey: null,
      targetKey: null,
      onArrived: () {
        arrivedCalled = true;
      },
    );

    await tester.pump();
    expect(find.text('banana'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();

    expect(arrivedCalled, isTrue);
    expect(find.text('banana'), findsNothing);
  });
}
