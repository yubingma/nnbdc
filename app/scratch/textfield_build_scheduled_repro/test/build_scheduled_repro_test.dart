import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 确定性复现（widget 测试，无需真机/无障碍）：
/// 证明 "Build scheduled during frame" 断言来自 Flutter 框架 TextField 内部的
/// `AnimatedBuilder(animation: controller)`，与业务代码无关。
///
/// 与业务日志完全一致的两条异常：
/// - "Build scheduled during frame."（断言本体）
/// - 由 ChangeNotifier 包装的上下文 "while dispatching notifications for
///   TextEditingController"（业务日志中的第二条异常头）
///
/// 触发时机说明：业务日志里输入法消息是在 drawFrame 的
/// flushSemantics → updateSemantics（同步 FFI）期间被引擎重入派发，属于
/// 帧内非 build 阶段。若在 build 阶段触发，会先撞上另一条断言
/// ("setState() or markNeedsBuild() called during build")，所以这里用
/// CustomPainter 的 paint 阶段（同为帧内非 build 阶段，与语义阶段等效）触发。
///
/// 运行：`flutter test`（本目录下）。
void main() {
  testWidgets('纯 TextField + 帧内(paint阶段) controller 通知 → 复现框架断言', (tester) async {
    final controller = TextEditingController();
    final errors = <FlutterErrorDetails>[];

    final oldHandler = FlutterError.onError;
    FlutterError.onError = errors.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // 任意普通 TextField 即可：框架内部自带 AnimatedBuilder(animation: controller)
              TextField(controller: controller),
              // paint 阶段修改 controller：模拟输入法消息在帧内(非 build 阶段)到达
              CustomPaint(
                painter: _PaintPhaseControllerUpdater(controller),
              ),
            ],
          ),
        ),
      ),
    );

    // 让框架在错误发生后收敛（重建被标记 dirty 的 TextField），再收尾
    await tester.pump();

    FlutterError.onError = oldHandler;
    controller.dispose();

    final rawMessages =
        errors.map((e) => e.exceptionAsString()).join('\n---\n');
    final contexts = errors
        .map((e) => e.context?.toString() ?? '(无上下文)')
        .join('\n---\n');
    // ignore: avoid_print
    print('捕获到的框架错误(异常本体):\n$rawMessages');
    // ignore: avoid_print
    print('捕获到的框架错误(上下文):\n$contexts');

    expect(
      rawMessages,
      contains('Build scheduled during frame'),
      reason: '断言应来自 Flutter 框架 TextField 内部 AnimatedBuilder 的帧内 setState',
    );
    expect(
      contexts,
      contains('while dispatching notifications for TextEditingController'),
      reason: '与业务应用日志中的第二条异常一致（ChangeNotifier 派发包装）',
    );
  });
}

/// 在 paint 阶段（帧内、非 build 阶段）修改 controller，触发其监听者（框架内部
/// AnimatedBuilder）的 setState —— 与业务日志中输入法消息在语义阶段到达等效。
class _PaintPhaseControllerUpdater extends CustomPainter {
  _PaintPhaseControllerUpdater(this.controller);

  final TextEditingController controller;

  @override
  void paint(Canvas canvas, Size size) {
    if (controller.text != 's') {
      controller.text = 's';
    }
  }

  @override
  bool shouldRepaint(covariant _PaintPhaseControllerUpdater oldDelegate) =>
      false;
}
