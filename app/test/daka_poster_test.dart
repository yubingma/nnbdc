import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/widget/daka_poster.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('打卡海报组件与数据模型测试', () {
    const testData = PosterData(
      userName: 'Alex',
      continuousDays: 28,
      todayWords: 30,
      memoryRate: 98,
      totalWords: 1420,
      dateStr: '2026.08.23',
    );

    test('PosterData 字段初始化正确', () {
      expect(testData.userName, 'Alex');
      expect(testData.continuousDays, 28);
      expect(testData.todayWords, 30);
      expect(testData.memoryRate, 98);
      expect(testData.totalWords, 1420);
      expect(testData.dateStr, '2026.08.23');
    });

    test('4 大 PosterThemeConfig 配置完整无误', () {
      expect(PosterThemeType.values.length, 4);
      for (final type in PosterThemeType.values) {
        final config = PosterThemeConfig.getConfig(type);
        expect(config.name.isNotEmpty, isTrue);
        expect(config.brandColor, isNotNull);
        expect(config.bgGradientStart, isNotNull);
        expect(config.bgGradientEnd, isNotNull);
      }
    });

    testWidgets('DakaPosterWidget 在 4 种标杆范式下均能正确渲染且包含关键数据', (tester) async {
      for (final type in PosterThemeType.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DakaPosterWidget(
                data: testData,
                themeType: type,
                width: 320,
              ),
            ),
          ),
        );

        // 验证关键文本呈现
        expect(find.text('泡泡单词'), findsAtLeastNWidgets(1));
        expect(find.text('扫码体验'), findsOneWidget);
        expect(find.text('Alex'), findsOneWidget);
      }
    });
  });
}
