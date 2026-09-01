import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
export '../widget/app_scaffold.dart';

/// 应用视觉主题风格枚举 (5 款风格截然不同、性格鲜明的专属美学)
enum AppThemeStyle {
  /// 晨曦流光 (DeepSeek 空灵科技，冰川极光冷蓝 + 高透毛玻璃)
  aurora('aurora', '晨曦流光', '空灵科技冰川蓝', Icons.auto_awesome_rounded),

  /// 经典翡翠 (扇贝经典护眼，温润抹茶米底 + 草本翡翠绿)
  emerald('emerald', '经典翡翠', '温润护眼抹茶绿', Icons.spa_rounded),

  /// 暮色落日 (温暖活力晚霞，落日暖橘 + 蜜桃暖色光晕)
  sunset('sunset', '暮色落日', '温暖活力晚霞橙', Icons.wb_twilight_rounded),

  /// 极简白墨 (极客硬朗线条，纯白高对比 + 纯黑墨水屏)
  minimal('minimal', '极简白墨', '极客纯粹高对比', Icons.contrast_rounded),

  /// 深邃曜黑 (沉浸夜间赛博，曜黑深空 + 极光霓虹翡翠)
  midnight('midnight', '深邃曜黑', '夜间沉浸护眼', Icons.dark_mode_rounded);

  final String code;
  final String label;
  final String description;
  final IconData icon;

  const AppThemeStyle(this.code, this.label, this.description, this.icon);

  static AppThemeStyle fromCode(String? code) {
    if (code == null) return AppThemeStyle.aurora;
    // 兼容旧代码 'jade' 映射为 'sunset'
    if (code == 'jade') return AppThemeStyle.sunset;
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
      // 1. 晨曦流光: 科技冰川冷蓝
      case AppThemeStyle.aurora:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFF0284C7), // 鲜明深邃天空科技蓝
          primaryLightColor: const Color(0xFF38BDF8),
          primaryDarkColor: const Color(0xFF0369A1),
          textPrimary: const Color(0xFF082F49), // 科技黛青
          textSecondary: const Color(0xFF0369A1),
          textMuted: const Color(0xFF64748B),
          cardBg: Colors.white.withValues(alpha: 0.70),
          cardBorder: Colors.white.withValues(alpha: 0.95),
          subtleBg: const Color(0xFFE0F2FE).withValues(alpha: 0.65),
          cardShadows: [
            BoxShadow(
              color: const Color(0xFF0284C7).withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
          isDark: false,
        );

      // 2. 经典翡翠: 扇贝温润草本绿
      case AppThemeStyle.emerald:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFF10B981), // 经典生机翡翠绿
          primaryLightColor: const Color(0xFF34D399),
          primaryDarkColor: const Color(0xFF059669),
          textPrimary: const Color(0xFF064E3B), // 深沉竹林绿
          textSecondary: const Color(0xFF047857),
          textMuted: const Color(0xFF6B7280),
          cardBg: const Color(0xFFFFFFFF),
          cardBorder: const Color(0x2E10B981),
          subtleBg: const Color(0xFFD1FAE5),
          cardShadows: [
            BoxShadow(
              color: const Color(0xFF065F46).withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
          isDark: false,
        );

      // 3. 暮色落日: 温暖落日活力橘
      case AppThemeStyle.sunset:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFFF97316), // 活力落日暖橘
          primaryLightColor: const Color(0xFFFB923C),
          primaryDarkColor: const Color(0xFFEA580C),
          textPrimary: const Color(0xFF431407), // 醇厚暖棕黑
          textSecondary: const Color(0xFF9A3412),
          textMuted: const Color(0xFF9E7162),
          cardBg: Colors.white.withValues(alpha: 0.88),
          cardBorder: const Color(0x3DF97316),
          subtleBg: const Color(0xFFFFEDD5),
          cardShadows: [
            BoxShadow(
              color: const Color(0xFFEA580C).withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
          isDark: false,
        );

      // 4. 极简白墨: 纯黑白硬朗高对比
      case AppThemeStyle.minimal:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFF18181B), // 极简纯粹曜黑
          primaryLightColor: const Color(0xFF3F3F46),
          primaryDarkColor: const Color(0xFF09090B),
          textPrimary: const Color(0xFF09090B), // 纯黑
          textSecondary: const Color(0xFF52525B),
          textMuted: const Color(0xFF71717A),
          cardBg: const Color(0xFFFFFFFF),
          cardBorder: const Color(0xFFD4D4D8),
          subtleBg: const Color(0xFFF4F4F5),
          cardShadows: const [],
          isDark: false,
        );

      // 5. 深邃曜黑: 赛博暗黑极光荧光绿
      case AppThemeStyle.midnight:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFF2CD88F), // 极光霓虹翡翠
          primaryLightColor: const Color(0xFF6EE7B7),
          primaryDarkColor: const Color(0xFF10B981),
          textPrimary: const Color(0xFFF8FAFC), // 月光高亮白
          textSecondary: const Color(0xFF94A3B8),
          textMuted: const Color(0xFF64748B),
          cardBg: const Color(0xFF0F1A17).withValues(alpha: 0.78),
          cardBorder: const Color(0x3D2CD88F),
          subtleBg: const Color(0xFF162B24),
          cardShadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
          isDark: true,
        );
    }
  }

  List<Color> get appBarGradient => [primaryColor, primaryDarkColor];
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
        secondary: cfg.primaryColor,
        surface: cfg.isDark ? const Color(0xFF14201D) : Colors.white,
        brightness: cfg.isDark ? Brightness.dark : Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
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
      tabBarTheme: TabBarThemeData(
        labelColor: cfg.primaryColor,
        unselectedLabelColor: cfg.textSecondary,
        indicatorColor: cfg.primaryColor,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
      ),
      chipTheme: ChipThemeData(
        selectedColor: cfg.primaryColor,
        backgroundColor: cfg.subtleBg,
        labelStyle: TextStyle(
          color: cfg.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cfg.cardBorder),
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
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cfg.primaryColor;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cfg.primaryColor.withValues(alpha: 0.5);
          return null;
        }),
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
    BuildContext? context,
    AppThemeStyle? themeStyle,
  }) {
    final titleWidget = title is Widget
        ? title
        : Text(title.toString(), style: const TextStyle(fontWeight: FontWeight.bold));

    List<Color> gradientColors = [gradientStartColor, gradientEndColor];
    if (themeStyle != null) {
      gradientColors = AppThemeConfig.of(themeStyle).appBarGradient;
    } else if (context != null) {
      try {
        final currentStyle = context.watch<DarkMode>().themeStyle;
        gradientColors = AppThemeConfig.of(currentStyle).appBarGradient;
      } catch (_) {}
    }

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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
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
    BuildContext? context,
    AppThemeStyle? themeStyle,
  }) {
    List<Color> gradientColors = colors ?? [gradientStartColor, gradientEndColor];
    if (colors == null) {
      if (themeStyle != null) {
        gradientColors = AppThemeConfig.of(themeStyle).appBarGradient;
      } else if (context != null) {
        try {
          final currentStyle = context.watch<DarkMode>().themeStyle;
          gradientColors = AppThemeConfig.of(currentStyle).appBarGradient;
        } catch (_) {}
      }
    }

    return BoxDecoration(
      gradient: LinearGradient(
        colors: gradientColors,
        begin: begin,
        end: end,
      ),
      borderRadius: borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
    );
  }
}
