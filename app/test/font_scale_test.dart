import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/theme/font_scale.dart';

void main() {
  group('AppFontScale 档位模型', () {
    test('三档系数符合约定，中档为 1.0', () {
      expect(AppFontScale.small.factor, 0.9);
      expect(AppFontScale.medium.factor, 1.0);
      expect(AppFontScale.large.factor, 1.15);
    });

    test('fromCode 能还原档位，未知或空值回落中档', () {
      expect(AppFontScale.fromCode('small'), AppFontScale.small);
      expect(AppFontScale.fromCode('large'), AppFontScale.large);
      expect(AppFontScale.fromCode('medium'), AppFontScale.medium);
      expect(AppFontScale.fromCode('bogus'), AppFontScale.medium);
      expect(AppFontScale.fromCode(null), AppFontScale.medium);
    });
  });

  group('AppFontScale.compose 在系统字号之上叠加', () {
    test('中档原样返回系统 scaler（不改变既有排版）', () {
      const system = TextScaler.linear(1.3);
      expect(AppFontScale.compose(system, AppFontScale.medium), same(system));
    });

    test('大/小档按系数缩放系统字号', () {
      const system = TextScaler.linear(1.2);
      expect(AppFontScale.compose(system, AppFontScale.large).scale(10), closeTo(10 * 1.2 * 1.15, 0.001));
      expect(AppFontScale.compose(system, AppFontScale.small).scale(10), closeTo(10 * 1.2 * 0.9, 0.001));
    });

    test('非线性系统 scaler 逐字号委派，不被线性近似抹平', () {
      // 模拟 Android 14+ 的非线性系统字号：小字放大更多
      final system = _NonLinearTextScaler();
      final composed = AppFontScale.compose(system, AppFontScale.large);

      // 小字号被系统放大 2 倍、大字号仅 1.05 倍，叠加 1.15 后应各自保留
      expect(composed.scale(10), closeTo(10 * 2.0 * 1.15, 0.001));
      expect(composed.scale(40), closeTo(40 * 1.05 * 1.15, 0.001));
    });
  });

  group('全局 TextScaler 传导到 Text', () {
    testWidgets('移除显式 textScaler 后，全局叠加后的 scaler 能真正放大文字', (tester) async {
      Future<double> widthAt(TextScaler scaler) async {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: scaler),
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text('MMMM', style: TextStyle(fontSize: 10)),
              ),
            ),
          ),
        );
        return tester.getSize(find.text('MMMM')).width;
      }

      final system = MediaQueryData().textScaler;
      final medium = await widthAt(AppFontScale.compose(system, AppFontScale.medium));
      final large = await widthAt(AppFontScale.compose(system, AppFontScale.large));
      final small = await widthAt(AppFontScale.compose(system, AppFontScale.small));

      expect(large / medium, closeTo(1.15, 0.02));
      expect(small / medium, closeTo(0.9, 0.02));
    });

    testWidgets('大档在系统字号之上继续叠加，而非取代系统字号', (tester) async {
      const system = TextScaler.linear(1.3);
      Future<double> widthAt(TextScaler scaler) async {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: system),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text('MMMM', style: const TextStyle(fontSize: 10), textScaler: scaler),
              ),
            ),
          ),
        );
        return tester.getSize(find.text('MMMM')).width;
      }

      final systemWidth = await widthAt(system);
      final composedWidth = await widthAt(AppFontScale.compose(system, AppFontScale.large));

      expect(composedWidth / systemWidth, closeTo(1.15, 0.02), reason: '大档应叠乘在系统字号之上');
    });
  });
}

/// 模拟非线性系统字号：字号越大，放大倍数越小。
final class _NonLinearTextScaler extends TextScaler {
  @override
  double scale(double fontSize) => fontSize <= 15 ? fontSize * 2.0 : fontSize * 1.05;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 1.5;
}
