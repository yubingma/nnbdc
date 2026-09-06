import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/enum.dart';
import '../state.dart';
export '../widget/app_scaffold.dart';

/// FSRS 评级标准语义色扩展（红、橙、绿、蓝，符合记忆算法与业界规范，不随应用品牌主题色变化）
extension FsrsRatingColorExt on FsrsRating {
  Color colorWithDark(bool isDark) {
    switch (this) {
      case FsrsRating.again:
        return isDark ? const Color(0xFFFF7E6C) : const Color(0xFFD32F2F); // 忘记: 鲜红
      case FsrsRating.hard:
        return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706); // 模糊: 琥珀橙
      case FsrsRating.good:
        return isDark ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C); // 良好: 生机翠绿
      case FsrsRating.easy:
        return isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7); // 轻松: 晴空科技蓝
    }
  }
}

/// 应用视觉主题风格枚举 (5 款风格截然不同、性格鲜明的专属美学)
enum AppThemeStyle {
  /// 晨曦流光 (DeepSeek 空灵科技，冰川极光冷蓝 + 高透毛玻璃)
  aurora('aurora', '晨曦流光', '空灵科技冰川蓝', Icons.auto_awesome_rounded),

  /// 黛蓝 (高级沉着，深灰蓝 + 中性深色文字)
  emerald('emerald', '黛蓝', '高级沉着黛蓝', Icons.spa_rounded),

  /// 暮色落日 (温暖活力晚霞，落日暖橘 + 蜜桃暖色光晕)
  sunset('sunset', '暮色落日', '温暖活力晚霞橙', Icons.wb_twilight_rounded),

  /// 极简白墨 (极客硬朗线条，纯白高对比 + 纯黑墨水屏)
  minimal('minimal', '极简白墨', '极客纯粹高对比', Icons.contrast_rounded),

  /// 深邃曜黑 (沉浸夜间赛博，曜黑深空 + 极光霓虹翡翠)
  midnight('midnight', '深邃曜黑', '夜间沉浸护眼', Icons.dark_mode_rounded),

  /// 京都朱砂 (Bear / 和风书卷，和纸纯粹米白 + 典雅朱砂赤红)
  crimson('crimson', '京都朱砂', '典雅书卷朱砂红', Icons.menu_book_rounded),

  /// 星云深靛 (Linear & Raycast，数字工艺深靛蓝 + 纯净冷灰)
  indigo('indigo', '星云深靛', '未来极客星云靛', Icons.blur_on_rounded),

  /// 鼠尾草森 (Gentler Streak / Apple，低饱和海盐青绿 + 视觉疗愈)
  sage('sage', '鼠尾草森', '海盐青木温润舒缓', Icons.grass_rounded),

  /// 暮光深空 (Arc & Linear Dark，曜石深空黑 + 霓虹紫罗兰光晕)
  twilight('twilight', '暮光深空', '曜石深空霓虹紫', Icons.nights_stay_rounded);

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
  bool get isDark => this == AppThemeStyle.midnight || this == AppThemeStyle.twilight;
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

  /// 温和次态/辅色（用于“不认识 / 再学学 / 弱化提醒”，包容温润不具警告感）
  final Color warmAccentColor;

  /// 未打卡（学习中）状态色：跟随当前主题已打卡主色，但明显浅淡（同色系层级）
  Color get dakaStudiedColor => primaryColor.withValues(alpha: isDark ? 0.45 : 0.36);

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
    required this.warmAccentColor,
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
          textPrimary: const Color(0xFF0C2136), // 现代高质感深冷灰黑
          textSecondary: const Color(0xFF335372), // 优雅次级灰
          textMuted: const Color(0xFF6B8BAA),
          cardBg: const Color(0x80FFFFFF), // 统一规格透光磨砂白 (50%)
          cardBorder: Colors.transparent, // 彻底消除灰色硬边框
          subtleBg: const Color(0x140284C7), // 轻透冷蓝微底色
          warmAccentColor: const Color(0xFFF97316), // 晨曦暖阳橙
          cardShadows: [
            BoxShadow(
              color: const Color(0xFF0C2136).withValues(alpha: 0.035),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
          isDark: false,
        );

      // 2. 经典翡翠: 扇贝经典护眼生机绿 / 不背单词原版翡翠晨雾
      case AppThemeStyle.emerald:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFF4A5A8A), // 高级沉着黛蓝
          primaryLightColor: const Color(0xFF7C8CB4),
          primaryDarkColor: const Color(0xFF37456C),
          textPrimary: const Color(0xFF1E242E), // 中性深墨（非蓝非绿，保证可读）
          textSecondary: const Color(0xFF464B54),
          textMuted: const Color(0xFF5C6068),
          cardBg: const Color(0x80FFFFFF), // 统一规格透光磨砂白 (50%)
          cardBorder: Colors.transparent, // 彻底消除灰色硬边框
          subtleBg: const Color(0x144A5A8A), // 黛蓝轻底
          warmAccentColor: const Color(0xFFFF7B40), // 温润珊瑚橙 (不认识/再学学专用)
          cardShadows: [
            BoxShadow(
              color: const Color(0xFF11211C).withValues(alpha: 0.03),
              blurRadius: 24,
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
          textPrimary: const Color(0xFF2E1912), // 高阶深炭灰黑
          textSecondary: const Color(0xFF6B4E44),
          textMuted: const Color(0xFF9E7D73),
          cardBg: const Color(0x80FFFFFF),
          cardBorder: Colors.transparent,
          subtleBg: const Color(0x14F97316),
          warmAccentColor: const Color(0xFFEA580C), // 沉静暖砖橙
          cardShadows: [
            BoxShadow(
              color: const Color(0xFF2E1912).withValues(alpha: 0.03),
              blurRadius: 24,
              offset: const Offset(0, 4),
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
          textMuted: const Color(0xFF8E8E93),
          cardBg: const Color(0x80FFFFFF),
          cardBorder: Colors.transparent,
          subtleBg: const Color(0x10000000),
          warmAccentColor: const Color(0xFF71717A), // 极客中性石板灰
          cardShadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
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
          cardBg: const Color(0xB818202F), // 统一规格深色抛光磨砂 (72%)
          cardBorder: Colors.transparent, // 消除生硬外边框
          subtleBg: const Color(0x1F2CD88F),
          warmAccentColor: const Color(0xFFF59E0B), // 暗夜琥珀金
          cardShadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
          isDark: true,
        );

      // 6. 京都朱砂: Bear 和风书卷朱砂赤红
      case AppThemeStyle.crimson:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFFE11D48), // 优雅朱砂赤红
          primaryLightColor: const Color(0xFFFB7185),
          primaryDarkColor: const Color(0xFFBE123C),
          textPrimary: const Color(0xFF301018), // 沉静暖和墨黑
          textSecondary: const Color(0xFF743442), // 暖石灰
          textMuted: const Color(0xFFAC707E),
          cardBg: const Color(0x80FFFFFF),
          cardBorder: Colors.transparent,
          subtleBg: const Color(0x14E11D48),
          warmAccentColor: const Color(0xFFD97706), // 和纸暖金琥珀
          cardShadows: [
            BoxShadow(
              color: const Color(0xFF301018).withValues(alpha: 0.03),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
          isDark: false,
        );

      // 7. 星云深靛: Linear & Raycast 极客工艺星云靛蓝
      case AppThemeStyle.indigo:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFF6366F1), // 招牌星云深靛蓝
          primaryLightColor: const Color(0xFF818CF8),
          primaryDarkColor: const Color(0xFF4F46E5),
          textPrimary: const Color(0xFF17183B), // 深空纯净黑
          textSecondary: const Color(0xFF474A82),
          textMuted: const Color(0xFF8286BC),
          cardBg: const Color(0x80FFFFFF),
          cardBorder: Colors.transparent,
          subtleBg: const Color(0x146366F1),
          warmAccentColor: const Color(0xFFFB923C), // 星云暖杏金
          cardShadows: [
            BoxShadow(
              color: const Color(0xFF17183B).withValues(alpha: 0.03),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
          isDark: false,
        );

      // 8. 鼠尾草森: Gentler Streak 风格治愈海盐青绿
      case AppThemeStyle.sage:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFF0D9488), // 舒缓海盐青木绿
          primaryLightColor: const Color(0xFF2DD4BF),
          primaryDarkColor: const Color(0xFF0F766E),
          textPrimary: const Color(0xFF0E2624), // 深青木墨黑
          textSecondary: const Color(0xFF395E5A),
          textMuted: const Color(0xFF6B9792),
          cardBg: const Color(0x80FFFFFF),
          cardBorder: Colors.transparent,
          subtleBg: const Color(0x140D9488),
          warmAccentColor: const Color(0xFFF97316), // 秋叶温和暖橙
          cardShadows: [
            BoxShadow(
              color: const Color(0xFF0E2624).withValues(alpha: 0.03),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
          isDark: false,
        );

      // 9. 暮光深空: Arc & Linear 曜石深空霓虹紫
      case AppThemeStyle.twilight:
        return AppThemeConfig(
          style: style,
          primaryColor: const Color(0xFFA855F7), // 霓虹星云紫
          primaryLightColor: const Color(0xFFD8B4FE),
          primaryDarkColor: const Color(0xFF9333EA),
          textPrimary: const Color(0xFFFAF5FF), // 月光亮白
          textSecondary: const Color(0xFFD8B4FE),
          textMuted: const Color(0xFFC084FC),
          cardBg: const Color(0xB818202F), // 统一规格深色抛光磨砂 (72%)
          cardBorder: Colors.transparent,
          subtleBg: const Color(0x1FA855F7),
          warmAccentColor: const Color(0xFFEC4899), // 暮光霓虹粉
          cardShadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
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

  /// 全局跨平台现代无衬线字体栈（对标 iOS 苹方 + Android 思源黑体，坚决杜绝回退到古典宋体/明体）
  static const List<String> sansSerifFallback = [
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Roboto',
    'Noto Sans SC',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'sans-serif',
  ];

  /// 现代修长挺拔西文/数字指标字体栈
  static const List<String> numberFontFallback = [
    'Roboto',
    'SF Pro Display',
    'SF Pro Text',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  /// 依据所选风格生成专属配套 ThemeData
  static ThemeData getThemeData(AppThemeStyle style) {
    final cfg = AppThemeConfig.of(style);
    final baseTypography = cfg.isDark ? Typography.material2021().white : Typography.material2021().black;
    final typographyWithFallbacks = baseTypography.apply(
      fontFamily: 'NotoSansSC',
      fontFamilyFallback: sansSerifFallback,
    );

    return ThemeData(
      fontFamily: 'NotoSansSC',
      fontFamilyFallback: sansSerifFallback,
      textTheme: typographyWithFallbacks,
      primaryTextTheme: typographyWithFallbacks,
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
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return cfg.textPrimary;
          }),
          fontSize: 13,
          fontWeight: FontWeight.w600,
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
