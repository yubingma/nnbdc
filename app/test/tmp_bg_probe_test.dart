import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/theme/app_theme_background.dart';
import 'package:nnbdc/theme/page_vibrancy.dart';
import 'package:nnbdc/widget/app_scaffold.dart';
import 'package:provider/provider.dart';

/// 临时验证脚本（用完即删）：按用户 macOS 窗口尺寸(805x602 逻辑点 / 2x)渲染背景层并出图，
/// 供外部逐像素采样对比「全局兜底背景」与「修复后选书页整页背景（AppScaffold）」。
void main() {
  Future<void> shoot(WidgetTester tester, Widget home, String name) async {
    tester.view.physicalSize = const Size(1610, 1204);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode()..setThemeStyle(AppThemeStyle.emerald),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: key,
            child: SizedBox(width: 805, height: 602, child: home),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('/Volumes/ssd/ppdc/tmp/ui_probe')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  testWidgets('probe: 全局兜底背景 vs 选书页背景', (tester) async {
    // 1) main.dart 那个不带 config 的全局兜底背景（修复前顶栏+Tab 条露出来的就是它）
    await shoot(
      tester,
      const AppThemeBackground(themeStyle: AppThemeStyle.emerald),
      'global_baseline',
    );

    // 2) 修复后的选书页整页结构：AppScaffold(selectBook) + 透明 AppBar + 44pt 的 Tab 条
    await shoot(
      tester,
      AppScaffold(
        vibrancy: PageVibrancy.selectBook,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          title: const SizedBox(width: 200),
          leading: const SizedBox(width: 32),
          actions: const [SizedBox(width: 32), SizedBox(width: 14)],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: SizedBox(
              height: 44,
              child: Row(children: const [SizedBox(width: 60), SizedBox(width: 60), SizedBox(width: 60)])),
          ),
        ),
        bottomNavigationBar: Container(height: 74, color: const Color(0x80FFFFFF)),
        body: const SizedBox.expand(),
      ),
      'select_book_page',
    );
  });
}
