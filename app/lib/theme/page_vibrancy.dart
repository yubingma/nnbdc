/// 页面级背景调参集中配置（全站唯一调整入口）
///
/// 每个页面一个 `PageVibrancyConfig` 值对象，统一描述该页背景的两项微调：
/// - [vibrancy]：提气强度。值越大越亮，无上限；但饱和度和明度被收紧到 [0,1]，
///   背景到纯白即封顶。`0` 即当前默认观感。
/// - [gradientSpan]：手机浅色背景的渐变幅度（顶部与底部的明度差）。值越大顶底
///   对比越强，`0` 为纯平色。以渐变中点 0.675 为轴对称推导，只改变落差不整体变亮。
///
/// 用法：页面在构造 `AppScaffold(vibrancy: ...)` 或 `AppThemeBackground(vibrancy: ...)`
/// 时引用这里的常量。统一调整某个页面的提气档位或渐变幅度，只需改本文件。
class PageVibrancyConfig {
  const PageVibrancyConfig({this.vibrancy = 0, this.gradientSpan = 0.23});

  /// 提气强度（0 即现状；越大越亮，到纯白封顶）
  final double vibrancy;

  /// 渐变幅度（顶部与底部的明度差；默认 0.23 即现状）
  final double gradientSpan;

  /// 现状默认值（0 提气 + 现状渐变幅度）
  static const PageVibrancyConfig none = PageVibrancyConfig();
}

/// 各页面背景调参常量引用
class PageVibrancy {
  PageVibrancy._();

  // ========== 当前已生效的非零档位 ==========

  /// 启动/欢迎页（浅色模式下整页明亮、透出主题色氛围）
  static const PageVibrancyConfig splash = PageVibrancyConfig(vibrancy: 3);

  /// 登录页（与启动页一致的明亮通透氛围）
  static const PageVibrancyConfig login = PageVibrancyConfig(vibrancy: 3);

  // ========== 其余页面（默认 0 = 现状，需要时在此调高） ==========

  /// 今日学习计划（首页「学习」Tab）
  static const PageVibrancyConfig todayPlan = PageVibrancyConfig(vibrancy: 2);

  /// 词表（首页「词表」Tab）
  static const PageVibrancyConfig wordLists = PageVibrancyConfig.none;

  /// 查词（首页「查词」Tab）
  static const PageVibrancyConfig search = PageVibrancyConfig.none;

  /// 我（首页「我」Tab）
  static const PageVibrancyConfig me = PageVibrancyConfig.none;

  /// 学习统计
  static const PageVibrancyConfig studyStats = PageVibrancyConfig.none;

  /// 记忆分布 / 复习分布
  static const PageVibrancyConfig reviewDistribution = PageVibrancyConfig.none;

  /// 消息
  static const PageVibrancyConfig message = PageVibrancyConfig.none;

  /// 单词详情
  static const PageVibrancyConfig wordDetail = PageVibrancyConfig.none;

  /// 选词书
  static const PageVibrancyConfig selectBook = PageVibrancyConfig.none;

  /// 完成页
  static const PageVibrancyConfig finish = PageVibrancyConfig.none;

  /// 农场
  static const PageVibrancyConfig farm = PageVibrancyConfig.none;

  /// 徽章墙
  static const PageVibrancyConfig badgeWall = PageVibrancyConfig.none;

  /// 游戏大厅
  static const PageVibrancyConfig game = PageVibrancyConfig.none;

  /// 随身听
  static const PageVibrancyConfig walkman = PageVibrancyConfig.none;

  /// 等级路径
  static const PageVibrancyConfig levelPath = PageVibrancyConfig.none;

  /// 提醒设置
  static const PageVibrancyConfig reminderSettings = PageVibrancyConfig.none;
}
