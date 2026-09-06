import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/theme/app_theme_background.dart';
import 'package:nnbdc/widget/theme_select_dialog.dart';
import 'package:provider/provider.dart';

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

        // 2. 亮色主题必须采用温润通透磨砂底与大圆角轻悬浮阴影
        if (!config.isDark && style != AppThemeStyle.minimal) {
          expect(config.cardBg, const Color(0x80FFFFFF), reason: '${style.name} 亮色卡片底应为统一规格透光磨砂白 (50%) 以保持通透呼吸感');
          expect(config.cardShadows.isNotEmpty, isTrue, reason: '${style.name} 必须具备微悬浮投影');
          expect(config.cardShadows.first.blurRadius >= 16, isTrue, reason: '阴影模糊半径需足够扩散以产生漫反射感');
        }

        // 3. 验证 ThemeData 生成完好
        final themeData = AppTheme.getThemeData(style);
        expect(themeData, isNotNull);
        expect(themeData.colorScheme.primary, config.primaryColor);
      }
    });

    test('青碧湖蓝 (emerald) 精准契合清新明快湖蓝青与温润珊瑚橙双态美学', () {
      final emerald = AppThemeConfig.of(AppThemeStyle.emerald);

      // 清新明快湖蓝青 #0891B2
      expect(emerald.primaryColor, const Color(0xFF0891B2));

      // 扇贝温润珊瑚橙 #FF7B40 (温和包容、不认识专用)
      expect(emerald.warmAccentColor, const Color(0xFFFF7B40));

      // 中性深墨字色
      expect(emerald.textPrimary, const Color(0xFF17262D));
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

    testWidgets('ThemeSelectDialog 毛玻璃弹窗能正常弹出、展示 9 种主题、点击切换并关闭', (tester) async {
      final darkMode = DarkMode();
      darkMode.setThemeStyle(AppThemeStyle.emerald);

      await tester.pumpWidget(
        ChangeNotifierProvider<DarkMode>.value(
          value: darkMode,
          child: MaterialApp(
            theme: AppTheme.getThemeData(AppThemeStyle.emerald),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('open_dialog_btn'),
                    onPressed: () {
                      ThemeSelectDialog.show(context);
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // 点击打开弹窗
      await tester.tap(find.byKey(const Key('open_dialog_btn')));
      await tester.pumpAndSettle();

      // 验证弹窗标题与毛玻璃容器
      expect(find.text('外观主题'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);

      // 验证 9 款主题均正常展示
      for (final style in AppThemeStyle.values) {
        expect(find.text(style.label), findsOneWidget);
      }

      // 点击选择 "京都朱砂" 主题
      await tester.tap(find.text('京都朱砂'));
      await tester.pumpAndSettle();
      expect(darkMode.themeStyle, AppThemeStyle.crimson);

      // 点击底部完成按钮关闭弹窗
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      // 弹窗已关闭
      expect(find.text('外观主题'), findsNothing);
    });
  });
}
