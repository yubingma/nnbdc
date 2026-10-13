import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/russia.dart';

/// 结算弹窗「对方视角」回切提示条的布局。
///
/// 用户真机反馈：`A RenderFlex overflowed by 36 pixels on the right`
/// （russia.dart 里这条提示条的 Row）。报错现场这一行只有 255 可用宽度，
/// 而 21 个汉字在 11px、1.15 倍字号下要占 270.7，再叠图标 14 与间距 6
/// 共 290.7，超出 35.7 —— 文字按自然宽度排版，单行根本塞不下。
void main() {
  Future<void> pumpHintBar(
    WidgetTester tester, {
    required double rowWidth,
    required double textScale,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            // 提示条左右内边距各 12、描边各 1，扣掉才是 Row 的可用宽度
            child: SizedBox(
              width: rowWidth + 24 + 2,
              child: RussiaPageState.resultBackHintBar(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('报错设备宽度（可用 255）与大字号下不溢出', (tester) async {
    await pumpHintBar(tester, rowWidth: 255, textScale: 1.15);

    expect(tester.takeException(), isNull);
    expect(find.text('点击上方【我方】即可随时切回自己的结算数据'), findsOneWidget);
  });

  testWidgets('窄屏（可用 221）与更大字号下也不溢出', (tester) async {
    await pumpHintBar(tester, rowWidth: 221, textScale: 1.5);

    expect(tester.takeException(), isNull);
    expect(find.text('点击上方【我方】即可随时切回自己的结算数据'), findsOneWidget);
  });
}
