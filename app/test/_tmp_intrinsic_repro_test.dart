import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 隔离复现：页面的 SingleChildScrollView + ConstrainedBox(minHeight) + Column(spaceBetween)
/// 内嵌 ReorderableListView(shrinkWrap)。
/// 验证：去掉 IntrinsicHeight 后不抛 "RenderShrinkWrappingViewport does not support
/// returning intrinsic dimensions"，且 Column 仍撑满 minHeight、spaceBetween 展开。
void main() {
  Future<BuildContext> pump(WidgetTester tester, {required bool withIntrinsic}) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              captured = context;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                  child: withIntrinsic
                      ? IntrinsicHeight(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              SizedBox(key: ValueKey('top'), height: 40),
                              SizedBox(key: ValueKey('mid'), height: 40),
                              SizedBox(key: ValueKey('bottom'), height: 40),
                            ],
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            SizedBox(key: ValueKey('top'), height: 40),
                            SizedBox(key: ValueKey('mid'), height: 40),
                            SizedBox(key: ValueKey('bottom'), height: 40),
                          ],
                        ),
                ),
              );
            },
          ),
        ),
      ),
    );
    return captured;
  }

  testWidgets('IntrinsicHeight + viewport throws', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                  child: IntrinsicHeight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 40),
                        ReorderableListView(
                          buildDefaultDragHandles: false,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          onReorder: (a, b) {},
                          children: const [
                            SizedBox(key: ValueKey('a'), height: 40),
                            SizedBox(key: ValueKey('b'), height: 40),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNotNull, reason: 'IntrinsicHeight 遇到懒加载视口应抛错');
  });

  testWidgets('Without IntrinsicHeight: no crash AND fills & spreads', (tester) async {
    // 设定固定浅平视口，便于断言尺寸
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pump(tester, withIntrinsic: false);
    expect(tester.takeException(), isNull, reason: '去掉 IntrinsicHeight 不应抛错');

    // 找到内部 Column 的渲染尺寸
    final Size colSize = tester.getSize(find.byType(Column).last);
    // ConstrainedBox minHeight = 800 - 48 = 752；Column 应撑满到 752
    expect(colSize.height, greaterThanOrEqualTo(752));

    // spaceBetween 展开：子项被拉开（bottom 与 top 的间距明显大于 40）
    final top = tester.getTopLeft(find.byKey(const ValueKey('top')));
    final bottom = tester.getTopLeft(find.byKey(const ValueKey('bottom')));
    // bottom 应在底边附近（无 padding 的底）
    expect(bottom.dy, greaterThan(top.dy + 300));
  });
}
