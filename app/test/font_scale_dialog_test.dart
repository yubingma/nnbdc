import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/font_scale.dart';
import 'package:nnbdc/widget/font_scale_dialog.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('字体大小弹窗在大档字号下不溢出，且能切换档位', (tester) async {
    final darkMode = DarkMode();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: darkMode,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: AppFontScale.compose(
                MediaQuery.of(context).textScaler,
                AppFontScale.large,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => FontScaleDialog.show(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 三档胶囊齐全，且不出现 RenderFlex 溢出
    expect(find.text('小'), findsOneWidget);
    expect(find.text('中'), findsOneWidget);
    expect(find.text('大'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 点击「大」应即时切换全局档位
    await tester.tap(find.text('大'));
    await tester.pumpAndSettle();
    expect(darkMode.fontScale, AppFontScale.large);

    await tester.tap(find.text('小'));
    await tester.pumpAndSettle();
    expect(darkMode.fontScale, AppFontScale.small);
  });
}
