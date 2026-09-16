import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/theme/font_scale.dart';

/// 复刻 MaterialApp.builder 中"系统字号 × 用户档位"的接线方式，
/// 验证该 MediaQuery 能覆盖路由页面与根导航器上的弹窗。
Widget _hostApp(AppFontScale scale, Widget home) {
  final darkModeState = _FakeFontScaleHolder(scale);
  return MaterialApp(
    builder: (context, child) {
      final mediaQuery = MediaQuery.of(context);
      return MediaQuery(
        data: mediaQuery.copyWith(
          textScaler: AppFontScale.compose(mediaQuery.textScaler, darkModeState.scale),
        ),
        child: child ?? const SizedBox.shrink(),
      );
    },
    home: home,
  );
}

class _FakeFontScaleHolder {
  _FakeFontScaleHolder(this.scale);
  final AppFontScale scale;
}

void main() {
  testWidgets('路由页面文字吃到全局字体档位', (tester) async {
    Future<double> widthAt(AppFontScale scale) async {
      await tester.pumpWidget(_hostApp(
        scale,
        const Align(
          alignment: Alignment.topLeft,
          child: Text('MMMM', style: TextStyle(fontSize: 10)),
        ),
      ));
      return tester.getSize(find.text('MMMM')).width;
    }

    final medium = await widthAt(AppFontScale.medium);
    final large = await widthAt(AppFontScale.large);
    expect(large / medium, closeTo(1.15, 0.02));
  });

  testWidgets('根导航器上的弹窗文字同样吃到全局字体档位', (tester) async {
    Future<double> widthAt(AppFontScale scale) async {
      // 先清空上一轮遗留的弹窗路由，避免其遮罩吞掉按钮点击
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_hostApp(
        scale,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showGeneralDialog<void>(
              context: context,
              transitionDuration: Duration.zero,
              pageBuilder: (dialogCtx, a1, a2) => const Align(
                alignment: Alignment.topLeft,
                child: Text('MMMM', style: TextStyle(fontSize: 10)),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return tester.getSize(find.text('MMMM')).width;
    }

    final medium = await widthAt(AppFontScale.medium);
    final large = await widthAt(AppFontScale.large);
    expect(large / medium, closeTo(1.15, 0.02), reason: '弹窗经根导航器路由，必须一并缩放');
  });
}
