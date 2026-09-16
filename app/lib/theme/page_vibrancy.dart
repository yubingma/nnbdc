import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 页面级背景调参集中配置（全站唯一调整入口）
///
/// 一个值对象统一描述某页背景与卡片的各项微调：
/// - [vibrancy]：提气强度。值越大越亮，无上限；但饱和度和明度被收紧到 [0,1]，
///   背景到纯白即封顶。`0` 即当前默认观感。
/// - [midLight]：手机浅色背景的"中部基准明度"，顶部/底部以其为中心偏移。
/// - [topShift] / [bottomShift]：顶部、底部相对中部基准的明度偏移量，可正可负，
///   甚至可反相（顶部比底部更重）。正值更亮，负值更深。
/// - [cardOpacity]：浅色模式下卡面（毛玻璃卡片底色）的不透明度，0~1。值越大卡片越实
///   (更不透明、更清晰明亮)，值越小越透。默认 0.50 即现状。
///
/// 设计：手机调好的成果即 [base] 基准（各页面常量在手机上就是这个值），
/// 平板无需单独调，调用 [forTablet] 把基准 × 各分字段系数即可复用手机成果。
class PageVibrancyConfig {
  const PageVibrancyConfig({
    this.vibrancy = 0,
    this.midLight = 0.675,
    this.topShift = 0.115,
    this.bottomShift = -0.115,
    this.cardOpacity = 0.50,
  });

  /// 提气强度（0 即现状；越大越亮，到纯白封顶）
  final double vibrancy;

  /// 中部基准明度（默认 0.675 即现状）
  final double midLight;

  /// 顶部相对中部的明度偏移量（默认 +0.115 即现状；负值则顶部更深）
  final double topShift;

  /// 底部相对中部的明度偏移量（默认 -0.115 即现状；正值则底部更亮）
  final double bottomShift;

  /// 浅色模式下卡面不透明度（默认 0.50 即现状；越大越实）
  final double cardOpacity;

  // ---------- 默认基准档（= 手机调好的观感） ----------
  /// 在手机上各页面实际使用的基准：提气 1.6 + 轻微渐变 + 卡片对齐 [AppThemeConfig.cardBg] 的 50% 磨砂白。
  static const PageVibrancyConfig base =
      PageVibrancyConfig(vibrancy: 1.6, topShift: 0.05, bottomShift: -0.05, cardOpacity: 0.5);

  // ---------- 平板对手机的分字段系数（<1 更收敛、>1 更张扬） ----------
  /// 平板相对手机「提气强度」的系数
  static const double tabletVibrancyRatio = 1;

  /// 平板相对手机「渐变偏移」的系数（作用于顶部/底部偏移的绝对值）
  static const double tabletGradientRatio = 1.6;

  /// 平板相对手机「卡片透明度」的系数（1 对应手机的全实）
  static const double tabletOpacityRatio = 1;

  /// 平板相对手机「中部基准明度」的系数（平板底色明度跟随收敛）
  static const double tabletMidLightRatio = 1;

  /// 平板档：把【本配置】的提气、渐变偏移、卡片透明度、中部明度各乘相应系数，
  /// 得到同页面在平板上的值。从而手机上的调整成果一键传导到平板，无需分别调。
  PageVibrancyConfig forTablet() => PageVibrancyConfig(
        vibrancy: vibrancy * tabletVibrancyRatio,
        midLight: midLight * tabletMidLightRatio,
        topShift: topShift * tabletGradientRatio,
        bottomShift: bottomShift * tabletGradientRatio,
        cardOpacity: cardOpacity * tabletOpacityRatio,
      );

  /// 本页卡片底色（唯一入口）：浅色用白、深色用深蓝底，统一以 [cardOpacity] 控制不透明度。
  /// [isNarrow] 为屏幕是否窄高屏(手机)：false(平板/方正屏)时自动按 [forTablet] 乘平板系数，
  /// 使手机的卡片透明度调整成果同样作用于平板。全站卡片应调用它而非直接写死透明白。
  Color cardColor(AppThemeConfig theme, {bool isNarrow = true}) {
    final cfg = isNarrow ? this : forTablet();
    final baseColor = theme.isDark ? const Color(0xFF18202F) : Colors.white;
    return baseColor.withValues(alpha: cfg.cardOpacity.clamp(0.0, 1.0));
  }

  /// 本页卡片阴影（与卡片透明度联动）：卡越透阴影越淡，避免透明卡久拖一圈黑影。
  /// 深色模式阴影略重、浅色更轻。[isNarrow] 为手机判定，含义见 [cardColor]。
  BoxShadow cardShadow(AppThemeConfig theme, {bool isNarrow = true}) {
    final cfg = isNarrow ? this : forTablet();
    // 卡面越实(接近 1)阴影越明显，越透(接近 0)阴影越淡；深色基准更轻，避免深底上拖黑影
    final spread = cfg.cardOpacity.clamp(0.0, 1.0);
    final alpha = (theme.isDark ? 0.14 : 0.05) * (0.3 + 0.7 * spread);
    return BoxShadow(
      color: Colors.black.withValues(alpha: alpha),
      blurRadius: 16,
      offset: const Offset(0, 4),
    );
  }
}

/// 各页面背景调参常量引用（均为手机/基准档；平板时由 AppScaffold 自动 × 系数）
class PageVibrancy {
  PageVibrancy._();

  /// 通用基准档
  static const PageVibrancyConfig base = PageVibrancyConfig.base;

  /// 启动/欢迎页（浅色模式下整页明亮、透出主题色氛围）
  static const PageVibrancyConfig splash = PageVibrancyConfig(vibrancy: 3);

  /// 登录页（与启动页一致的明亮通透氛围）
  static const PageVibrancyConfig login = PageVibrancyConfig(vibrancy: 3);

  /// 今日学习计划（首页「学习」Tab）：背景比基准收敛一档。
  /// 基准 1.6 会把浅色模式顶部背景提到近白(≈244)，卡片(50% 磨砂白)叠上去只差 4 个色阶，
  /// 分组结构整片糊掉；1.2 让顶部回落到 ≈232，卡片对比度回到 ≈11 个色阶，卡片重新"浮"起来。
  static const PageVibrancyConfig todayPlan =
      PageVibrancyConfig(vibrancy: 1.2, topShift: 0.05, bottomShift: -0.05, cardOpacity: 0.5);

  /// 词表（首页「词表」Tab）
  static const PageVibrancyConfig wordLists = PageVibrancyConfig.base;

  /// 查词（首页「查词」Tab）
  static const PageVibrancyConfig search = PageVibrancyConfig.base;

  /// 单词列表（词库详情页）
  static const PageVibrancyConfig wordList = PageVibrancyConfig.base;

  /// 我（首页「我」Tab）
  static const PageVibrancyConfig me = PageVibrancyConfig.base;

  /// 学习统计
  static const PageVibrancyConfig studyStats = PageVibrancyConfig.base;

  /// 记忆分布 / 复习分布
  static const PageVibrancyConfig reviewDistribution =
      PageVibrancyConfig(vibrancy: 1.2, topShift: 0.05, bottomShift: -0.05, cardOpacity: 0.65);

  /// 消息
  static const PageVibrancyConfig message = PageVibrancyConfig.base;

  /// 单词详情
  static const PageVibrancyConfig wordDetail = PageVibrancyConfig.base;

  /// 选词书
  static const PageVibrancyConfig selectBook = PageVibrancyConfig.base;

  /// 完成页
  static const PageVibrancyConfig finish = PageVibrancyConfig.base;

  /// 农场
  static const PageVibrancyConfig farm = PageVibrancyConfig.base;

  /// 徽章墙
  static const PageVibrancyConfig badgeWall = PageVibrancyConfig.base;

  /// 游戏大厅
  static const PageVibrancyConfig game = PageVibrancyConfig.base;

  /// 随身听
  static const PageVibrancyConfig walkman = PageVibrancyConfig.base;

  /// 等级路径
  static const PageVibrancyConfig levelPath = PageVibrancyConfig.base;

  /// 提醒设置
  static const PageVibrancyConfig reminderSettings = PageVibrancyConfig.base;
}
