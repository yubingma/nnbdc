import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 全局自适应主题背景层组件 (对标不背单词原版：整屏"浅→深"纵向渐变带)
///
/// 区别于旧版的"点状模糊光斑 + 平铺底色"(会中间重、边缘快速变淡)，
/// 这里改为**贯穿整个屏幕高度**的纵向渐变：顶部一抹轻盈高光，往下缓慢、
/// 均匀地沉到带主题色相的更深底色 —— 色调铺满全屏，无中心热点、无边缘骤退。
class AppThemeBackground extends StatelessWidget {
  final AppThemeStyle themeStyle;
  final bool? isDarkMode;

  const AppThemeBackground({
    super.key,
    required this.themeStyle,
    this.isDarkMode,
  });

  bool _resolveIsDark(BuildContext context) {
    if (isDarkMode != null) return isDarkMode!;
    return themeStyle.isDark;
  }

  @override
  Widget build(BuildContext context) {
    final dark = _resolveIsDark(context);
    final (top, mid, bottom) = dark ? _darkGradient(themeStyle) : _lightGradient(themeStyle);
    return _buildVerticalGradient(top, mid, bottom);
  }

  /// 统一垂直渐变构建器：三段色贯穿全屏，上半段保持轻盈、下半段更快沉深
  Widget _buildVerticalGradient(Color top, Color mid, Color bottom) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, mid, bottom],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }

  (Color, Color, Color) _lightGradient(AppThemeStyle style) => switch (style) {
        // 校准：轻盈通透的光感(顶部一段柔亮高光) + 低饱和的整屏纵向渐变。
        // 注意不要压得偏灰偏暗 —— 高级感依赖"明亮透光"而非"压暗的中灰"。
        AppThemeStyle.aurora => (
            const Color(0xFFC5D5E1),
            const Color(0xFFB9C9D4),
            const Color(0xFFA1B2BC),
          ),
        AppThemeStyle.emerald => (
            const Color(0xFFCAD5CF),
            const Color(0xFFBBCAC4),
            const Color(0xFF9FB4AF),
          ),
        AppThemeStyle.sunset => (
            const Color(0xFFE1D7D2),
            const Color(0xFFD6CAC4),
            const Color(0xFFC0B2A9),
          ),
        AppThemeStyle.minimal => (
            const Color(0xFFD3D5D8),
            const Color(0xFFC6C8CC),
            const Color(0xFFAEB0B4),
          ),
        AppThemeStyle.midnight => (
            const Color(0xFFC5D7D1),
            const Color(0xFFB8CCC5),
            const Color(0xFF9FB6AF),
          ),
        AppThemeStyle.crimson => (
            const Color(0xFFE1D3D5),
            const Color(0xFFD5C5C8),
            const Color(0xFFBFAAAF),
          ),
        AppThemeStyle.indigo => (
            const Color(0xFFD1D4E4),
            const Color(0xFFC4C6D7),
            const Color(0xFFABACBE),
          ),
        AppThemeStyle.sage => (
            const Color(0xFFC6D5D3),
            const Color(0xFFB9C8C6),
            const Color(0xFFA0B0AE),
          ),
        AppThemeStyle.twilight => (
            const Color(0xFFD9D2E2),
            const Color(0xFFCDC5D6),
            const Color(0xFFB6ADBE),
          ),
      };

  (Color, Color, Color) _darkGradient(AppThemeStyle style) => switch (style) {
        AppThemeStyle.aurora => (
            const Color(0xFF072032),
            const Color(0xFF061624),
            const Color(0xFF040D17),
          ),
        AppThemeStyle.emerald => (
            const Color(0xFF0F221C),
            const Color(0xFF0C1A16),
            const Color(0xFF0A1411),
          ),
        AppThemeStyle.sunset => (
            const Color(0xFF280E06),
            const Color(0xFF1D0A04),
            const Color(0xFF140703),
          ),
        AppThemeStyle.minimal => (
            const Color(0xFF17181C),
            const Color(0xFF111216),
            const Color(0xFF0C0D10),
          ),
        AppThemeStyle.midnight => (
            const Color(0xFF0B1D18),
            const Color(0xFF091511),
            const Color(0xFF060E0B),
          ),
        AppThemeStyle.crimson => (
            const Color(0xFF270810),
            const Color(0xFF1D060C),
            const Color(0xFF140408),
          ),
        AppThemeStyle.indigo => (
            const Color(0xFF12142E),
            const Color(0xFF0D0E22),
            const Color(0xFF080917),
          ),
        AppThemeStyle.sage => (
            const Color(0xFF09201E),
            const Color(0xFF071716),
            const Color(0xFF05100F),
          ),
        AppThemeStyle.twilight => (
            const Color(0xFF1C0B2C),
            const Color(0xFF150821),
            const Color(0xFF0E0516),
          ),
      };
}
