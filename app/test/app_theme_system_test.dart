import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/theme/app_theme_background.dart';

void main() {
  group('AppThemeStyle & AppThemeConfig 全局质感与扇贝设计系统测试', () {
    test('全部 9 款主题均已配置完整的 warmAccentColor、主色及微悬浮阴影', () {
      for (final style in AppThemeStyle.values) {
        final config = AppThemeConfig.of(style);

        // 1. 验证基础必填属性
        expect(config.primaryColor, isNotNull, reason: '${style.name} primaryColor 不能为空');
        expect(config.primaryLightColor, isNotNull);
        expect(config.primaryDarkColor, isNotNull);
        expect(config.textPrimary, isNotNull);
        expect(config.warmAccentColor, isNotNull, reason: '${style.name} 必须配置温和次态色彩');
        expect(config.cardShadows, isNotNull);

        // 2. 亮色主题必须采用纯白卡片底与大圆角轻悬浮阴影
        if (!config.isDark && style != AppThemeStyle.minimal) {
          expect(config.cardBg, Colors.white, reason: '${style.name} 亮色卡片底应为纯白以保持通透质感');
          expect(config.cardShadows.isNotEmpty, isTrue, reason: '${style.name} 必须具备微悬浮投影');
          expect(config.cardShadows.first.blurRadius >= 16, isTrue, reason: '阴影模糊半径需足够扩散以产生漫反射感');
        }

        // 3. 验证 ThemeData 生成完好
        final themeData = AppTheme.getThemeData(style);
        expect(themeData, isNotNull);
        expect(themeData.colorScheme.primary, config.primaryColor);
      }
    });

    test('经典翡翠 (emerald) 精准契合扇贝生机绿与温润珊瑚橙双态美学', () {
      final emerald = AppThemeConfig.of(AppThemeStyle.emerald);

      // 扇贝经典生机绿 #00BA76
      expect(emerald.primaryColor, const Color(0xFF00BA76));

      // 扇贝温润珊瑚橙 #FF7B40 (温和包容、不认识专用)
      expect(emerald.warmAccentColor, const Color(0xFFFF7B40));

      // 护眼深炭墨字色
      expect(emerald.textPrimary, const Color(0xFF192520));
    });

    test('AppThemeBackground 能针对各主题正常构建 Widget 不报错', () {
      for (final style in AppThemeStyle.values) {
        final bg = AppThemeBackground(themeStyle: style);
        expect(bg, isNotNull);
      }
    });

    testWidgets('全部主题下的 ChipThemeData 均具备良好的选中态高亮白与未选中态配色', (tester) async {
      for (final style in AppThemeStyle.values) {
        final themeData = AppTheme.getThemeData(style);
        final cfg = AppThemeConfig.of(style);

        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(style),
            theme: themeData,
            home: Scaffold(
              body: Column(
                children: [
                  FilterChip(
                    key: const Key('selected_chip'),
                    label: const Text('美音 (_us)'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  FilterChip(
                    key: const Key('unselected_chip'),
                    label: const Text('英音 (_uk)'),
                    selected: false,
                    onSelected: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final selectedTextFinder = find.descendant(
          of: find.byKey(const Key('selected_chip')),
          matching: find.text('美音 (_us)'),
        );
        final selectedDTS = tester.widget<DefaultTextStyle>(
          find.ancestor(of: selectedTextFinder, matching: find.byType(DefaultTextStyle)).first,
        );
        expect(selectedDTS.style.color, Colors.white, reason: '${style.name} 选中文字应为纯白');

        final unselectedTextFinder = find.descendant(
          of: find.byKey(const Key('unselected_chip')),
          matching: find.text('英音 (_uk)'),
        );
        final unselectedDTS = tester.widget<DefaultTextStyle>(
          find.ancestor(of: unselectedTextFinder, matching: find.byType(DefaultTextStyle)).first,
        );
        expect(unselectedDTS.style.color, cfg.textPrimary, reason: '${style.name} 未选中文字应为 textPrimary');

        expect(themeData.chipTheme.checkmarkColor, Colors.white, reason: '${style.name} 对勾应为纯白');
      }
    });
  });
}
