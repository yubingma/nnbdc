import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/study_date_rules.dart';
import 'package:nnbdc/state.dart';
import 'package:provider/provider.dart';

void main() {
  for (final width in [320.0, 360.0, 390.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.5]) {
      testWidgets('${width.toInt()}dp 屏幕在 ${scale}x 字号缩放下进入学习日期说明页不发生 RenderFlex overflow', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ChangeNotifierProvider<DarkMode>.value(
            value: DarkMode(),
            child: MaterialApp(
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                return MediaQuery(
                  data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: const StudyDateRulesPage(),
            ),
          ),
        );

        await tester.pumpAndSettle();
      });
    }
  }
}
