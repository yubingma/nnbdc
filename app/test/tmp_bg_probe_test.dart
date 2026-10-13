import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/theme/app_theme_background.dart';
import 'package:nnbdc/theme/page_vibrancy.dart';

/// 临时验证脚本（用完即删）：按用户 macOS 窗口尺寸(805x602 逻辑点 / 2x)渲染
/// 「修复后选书页整页使用的背景」并出图，供外部逐像素采样。
void main() {
  testWidgets('probe: 选书页背景（平board 档，AppScaffold 实际传入值）', (tester) async {
    tester.view.physicalSize = const Size(1610, 1204);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final cfg = PageVibrancy.selectBook.forTablet();
    debugPrint('PROBE cfg ${cfg.vibrancy} ${cfg.midLight} ${cfg.topShift} ${cfg.bottomShift}');

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 805,
            height: 602,
            child: AppThemeBackground(
              themeStyle: AppThemeStyle.emerald,
              vibrancy: cfg.vibrancy,
              midLight: cfg.midLight,
              topShift: cfg.topShift,
              bottomShift: cfg.bottomShift,
            ),
          ),
        ),
      ),
    );
    debugPrint('PROBE pumped');
    await tester.pump();

    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    debugPrint('PROBE boundary');
    final image = await boundary.toImage(pixelRatio: 2.0);
    debugPrint('PROBE image ${image.width}x${image.height}');
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('/Volumes/ssd/ppdc/tmp/ui_probe')..createSync(recursive: true);
    File('${dir.path}/select_book_page.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('PROBE written');
  });
}
