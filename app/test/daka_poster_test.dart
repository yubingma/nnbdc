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

    test('6 款 PosterThemeConfig 配置完整无误', () {
      for (final type in PosterThemeType.values) {
        final config = PosterThemeConfig.getConfig(type);
        expect(config.name.isNotEmpty, isTrue);
        expect(config.tagText.isNotEmpty, isTrue);
        expect(config.quoteMain.isNotEmpty, isTrue);
        expect(config.quoteSub.isNotEmpty, isTrue);
        expect(config.dateTag.isNotEmpty, isTrue);
      }
    });

    testWidgets('DakaPosterWidget 在所有 6 款主题下均能正确渲染且包含关键数据', (tester) async {
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

        // 验证文本呈现
        expect(find.text('泡泡单词'), findsOneWidget);
        expect(find.text('28'), findsOneWidget);
        expect(find.text('30 词'), findsOneWidget);
        expect(find.text('98%'), findsOneWidget);
        expect(find.text('1,420'), findsOneWidget);
        expect(find.text('Alex'), findsOneWidget);
      }
    });
  });
}
