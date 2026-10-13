import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/game.dart';
import 'package:nnbdc/theme/app_theme.dart';

/// 「对战玩法规则」弹窗在放大字号下的布局。
///
/// 用户反馈：iPad 上按钮「我知道了」的文字下半部分被遮挡。
/// 根因是按钮高度被写死成 44px，而项目允许系统字号参与排版
/// （`main.dart` 用 `AppFontScale.compose` 把系统字号叠进整棵树）——
/// iPad 上系统字号调大后，14px 的文字行高超过 44px，下半截就被容器裁掉了。
void main() {
  const AppThemeStyle style = AppThemeStyle.emerald;

  Future<void> pumpRulesDialog(WidgetTester tester, {required double textScale}) async {
    // iPad 竖屏逻辑尺寸，避免用手机尺寸测出"看起来没问题"的假象
    tester.view.physicalSize = const Size(1640, 2360);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: GameRulesDialog(
              themeStyle: style,
              themeConfig: AppThemeConfig.of(style),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('iPad 系统大字号（3 倍）下，按钮文字不被裁切', (tester) async {
    await pumpRulesDialog(tester, textScale: 3.0);

    final Size buttonSize = tester.getSize(find.byType(ElevatedButton));
    // 文字被写死高度压住时，它的布局尺寸会被压小，看不出问题；
    // 必须问"这段话在无限高度下需要多高"，才能发现容器装不下
    final RenderBox label = tester.renderObject(find.text('我知道了'));
    final double neededHeight = label.getMaxIntrinsicHeight(double.infinity);

    expect(buttonSize.height, greaterThanOrEqualTo(neededHeight),
        reason: '按钮 $buttonSize 装不下文字需要的 $neededHeight，下半截会被裁掉');
  });

  testWidgets('iPad 系统大字号（3 倍）下，规则序号圆圈也不裁字', (tester) async {
    await pumpRulesDialog(tester, textScale: 3.0);

    final RenderBox indexLabel = tester.renderObject(find.text('1'));
    final double neededHeight = indexLabel.getMaxIntrinsicHeight(double.infinity);

    expect(indexLabel.size.height, greaterThanOrEqualTo(neededHeight),
        reason: '序号文字被固定大小的圆圈压扁了');
  });

  testWidgets('iPad 系统大字号（3 倍）下，弹窗内容不溢出屏幕', (tester) async {
    await pumpRulesDialog(tester, textScale: 3.0);

    expect(tester.takeException(), isNull, reason: '弹窗内容溢出了，应该有滚动兜底');
  });

  testWidgets('常规字号下按钮仍是紧凑的 44 高', (tester) async {
    await pumpRulesDialog(tester, textScale: 1.0);

    final Size buttonSize = tester.getSize(find.byType(ElevatedButton));
    expect(buttonSize.height, greaterThanOrEqualTo(44.0));
    expect(buttonSize.height, lessThan(60.0), reason: '常规字号下不该被撑得过高');
  });
}
