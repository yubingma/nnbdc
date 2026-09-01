import 'package:flutter/material.dart';

/// 应用视觉主题风格枚举
enum AppThemeStyle {
  /// 晨曦流光 (DeepSeek 空灵风，轻柔 4 色漫射微光 + 科技青蓝 + 高透毛玻璃)
  aurora('aurora', '晨曦流光', 'DeepSeek 空灵美学', Icons.auto_awesome_rounded),

  /// 经典翡翠 (扇贝温润护眼风，纯净淡雅米白底 + 经典翡翠绿 + 纯净实体微阴影)
  emerald('emerald', '经典翡翠', '温润护眼专注', Icons.spa_rounded),

  /// 东方羊脂玉 (东方凝脂雅致风，羊脂渐变 + 古典碧青 + 凝脂微透)
  jade('jade', '羊脂白玉', '东方凝脂雅韵', Icons.lens_blur_rounded),

  /// 极简白墨 (极客专注风，纯白底 + 纯粹曜黑 + 墨水屏高对比)
  minimal('minimal', '极简白墨', '极客纯粹高对比', Icons.contrast_rounded),

  /// 深邃曜黑 (沉浸夜间风，深邃曜黑底 + 霓虹翡翠 + 暗黑高透卡片)
  midnight('midnight', '深邃曜黑', '夜间沉浸护眼', Icons.dark_mode_rounded);

  final String code;
  final String label;
  final String description;
  final IconData icon;

  const AppThemeStyle(this.code, this.label, this.description, this.icon);

  static AppThemeStyle fromCode(String? code) {
    if (code == null) return AppThemeStyle.aurora;
    for (final style in AppThemeStyle.values) {
      if (style.code == code) return style;
    }
    return AppThemeStyle.aurora;
  }

  /// 该主题是否为深底/暗色主题
  bool get isDark => this == AppThemeStyle.midnight;
}

/// 主题全套配色与质感配置模型
class AppThemeConfig {
  final AppThemeStyle style;
  final Color primaryColor;
  final Color primaryLightColor;
  final Color primaryDarkColor;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color cardBg;
  final Color cardBorder;
  final Color subtleBg;
  final List<BoxShadow> cardShadows;
  final bool isDark;

  const AppThemeConfig({
    required this.style,
    required this.primaryColor,
    required this.primaryLightColor,
    required this.primaryDarkColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.cardBg,
    required this.cardBorder,
    required this.subtleBg,
    required this.cardShadows,
    required this.isDark,
  });

  static AppThemeConfig of(AppThemeStyle style) {
    switch (style) {
      case AppThemeStyle.aurora:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFF0EA5E9), // 晨曦科技天空蓝
          primaryLightColor: const Color(0xFF38BDF8),
          primaryDarkColor: const Color(0xFF0284C7),
          textPrimary: const Color(0xFF0F282F),
          textSecondary: const Color(0xFF3B6771),
          textMuted: const Color(0xFF6A919B),
          cardBg: Colors.white.withValues(alpha: 0.68),
          cardBorder: Colors.white.withValues(alpha: 0.90),
          subtleBg: Colors.white.withValues(alpha: 0.50),
          cardShadows: [
            BoxShadow(
              color: const Color(0xFF0284C7).withValues(alpha: 0.06),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
          isDark: false,
        );
      case AppThemeStyle.emerald:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFF18BA7C), // 扇贝经典护眼绿
          primaryLightColor: const Color(0xFF2CD88F),
          primaryDarkColor: const Color(0xFF109E69),
          textPrimary: const Color(0xFF142823),
          textSecondary: const Color(0xFF43655D),
          textMuted: const Color(0xFF73938C),
          cardBg: Colors.white,
          cardBorder: const Color(0x1418BA7C),
          subtleBg: const Color(0xFFEDF5F2),
          cardShadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
          isDark: false,
        );
      case AppThemeStyle.jade:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFF059669), // 东方典雅碧青
          primaryLightColor: const Color(0xFF10B981),
          primaryDarkColor: const Color(0xFF047857),
          textPrimary: const Color(0xFF1A2522),
          textSecondary: const Color(0xFF475B56),
          textMuted: const Color(0xFF7B8F8A),
          cardBg: Colors.white.withValues(alpha: 0.88),
          cardBorder: const Color(0x28059669),
          subtleBg: const Color(0xFFEBF5F0),
          cardShadows: [
            BoxShadow(
              color: const Color(0xFF047857).withValues(alpha: 0.07),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
          isDark: false,
        );
      case AppThemeStyle.minimal:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFF18181B), // 极简曜黑
          primaryLightColor: const Color(0xFF27272A),
          primaryDarkColor: const Color(0xFF09090B),
          textPrimary: const Color(0xFF09090B),
          textSecondary: const Color(0xFF52525B),
          textMuted: const Color(0xFF71717A),
          cardBg: Colors.white,
          cardBorder: const Color(0xFFE4E4E7),
          subtleBg: const Color(0xFFF4F4F5),
          cardShadows: const [],
          isDark: false,
        );
      case AppThemeStyle.midnight:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFF2CD88F), // 霓虹翡翠
          primaryLightColor: const Color(0xFF6EE7B7),
          primaryDarkColor: const Color(0xFF10B981),
          textPrimary: const Color(0xFFF1F5F9),
          textSecondary: const Color(0xFF94A3B8),
          textMuted: const Color(0xFF64748B),
          cardBg: const Color(0xFF111E1B).withValues(alpha: 0.75),
          cardBorder: Colors.white.withValues(alpha: 0.12),
          subtleBg: const Color(0xFF182824),
          cardShadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
          isDark: true,
        );
    }
  }
}

class AppTheme {
  // 默认全局主色（扇贝绿，向下兼容）
  static const Color primaryColor = Color(0xFF18BA7C);
  static const Color primaryDarkColor = Color(0xFF109E69);
  static const Color primaryLightColor = Color(0xFF2CD88F);
  static const Color gradientStartColor = Color(0xFF18BA7C);
  static const Color gradientEndColor = Color(0xFF109E69);

  /// 依据所选风格生成专属配套 ThemeData
  static ThemeData getThemeData(AppThemeStyle style) {
    final cfg = AppThemeConfig.of(style);
    return ThemeData(
      fontFamily: 'NotoSansSC',
      colorScheme: ColorScheme.fromSeed(
        seedColor: cfg.primaryColor,
        primary: cfg.primaryColor,
        primaryContainer: cfg.primaryLightColor,
        surface: cfg.isDark ? const Color(0xFF1E1E1E) : Colors.white,
        brightness: cfg.isDark ? Brightness.dark : Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cfg.primaryColor,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cfg.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cfg.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: cfg.primaryColor, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: cfg.isDark ? Colors.white12 : Colors.grey.withValues(alpha: 0.1), width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: cfg.primaryColor,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: cfg.primaryColor,
        unselectedItemColor: cfg.isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
      ),
    );
  }

  // 兼容旧调用
  static ThemeData lightTheme() => getThemeData(AppThemeStyle.aurora);
  static ThemeData darkTheme() => getThemeData(AppThemeStyle.midnight);

  /// 创建渐变背景的 AppBar
  static PreferredSizeWidget createGradientAppBar({
    required dynamic title,
    List<Widget>? actions,
    Widget? leading,
    bool centerTitle = true,
    double elevation = 0,
    PreferredSizeWidget? bottom,
    double? toolbarHeight,
    bool automaticallyImplyLeading = true,
  }) {
    final titleWidget = title is Widget
        ? title
        : Text(title.toString(), style: const TextStyle(fontWeight: FontWeight.bold));
    return AppBar(
      title: titleWidget,
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
      elevation: elevation,
      bottom: bottom,
      toolbarHeight: toolbarHeight,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [gradientStartColor, gradientEndColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }

  /// 创建通用的渐变 BoxDecoration
  static BoxDecoration createGradientDecoration({
    double borderRadius = 0,
    List<Color>? colors,
    Alignment begin = Alignment.topLeft,
    Alignment end = Alignment.bottomRight,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: colors ?? [gradientStartColor, gradientEndColor],
        begin: begin,
        end: end,
      ),
      borderRadius: borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
    );
  }
}
