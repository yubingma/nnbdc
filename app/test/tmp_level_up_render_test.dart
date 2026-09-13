import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/level_util.dart';
import 'package:nnbdc/widget/level_up_dialog.dart';
import 'package:provider/provider.dart';

/// 一次性渲染验证: 把真实弹窗盖在密集词表上截图, 人工核对毛玻璃与可读性。
void main() {
  for (final theme in [AppThemeStyle.emerald, AppThemeStyle.twilight]) {
    testWidgets('render ${theme.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final darkMode = DarkMode();
      darkMode.setThemeStyle(theme);

      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<DarkMode>.value(
            value: darkMode,
            child: MaterialApp(
              home: Scaffold(
                body: ListView(
                  children: [
                    for (final w in const [
                      'devise',
                      'engage',
                      'fertile',
                      'wan',
                      'continual',
                      'pillow',
                      'guest',
                      'monitor',
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        child: Text(
                          '$w   [ɪnˈɡeɪdʒ]  释义',
                          style: const TextStyle(
                            fontSize: 26,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      LevelUpDialog.show(
        tester.element(find.byType(Scaffold)),
        level: LevelUtil.getTitle(4),
        rewardBubbles: 120,
      );
      await tester.pumpAndSettle();

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/level_up_${theme.name}.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }
}
