/// 页面级背景调参集中配置（全站唯一调整入口）
///
/// 每个页面一个 `PageVibrancyConfig` 值对象，统一描述该页背景与卡片的各项微调：
/// - [vibrancy]：提气强度。值越大越亮，无上限；但饱和度和明度被收紧到 [0,1]，
///   背景到纯白即封顶。`0` 即当前默认观感。
/// - [midLight]：手机浅色背景的"中部基准明度"，顶部/底部以其为中心偏移。
/// - [topShift] / [bottomShift]：顶部、底部相对中部基准的明度偏移量，可正可负，
///   甚至可反相（顶部比底部更重）。正值更亮，负值更深。
/// - [cardOpacity]：浅色模式下卡面（毛玻璃卡片底色）的不透明度，0~1。值越大卡片越实
///   (更不透明、更清晰明亮)，值越小越透。默认 0.50 即现状。
///
/// 平板档为手机档的"分字段系数"推导：vibrancy、渐变偏移、cardOpacity 各用一个系数，
/// 系数即平板相对手机的比例（<1 更收敛、>1 更张扬）。
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

  // ---------- 手机基准档 ----------
  // 当前线上观感的统一基准：提气 1.6 + 轻微渐变 + 卡片全实。
  static const PageVibrancyConfig phoneDefault =
      PageVibrancyConfig(vibrancy: 1.6, topShift: 0.05, bottomShift: -0.05, cardOpacity: 1);

  // ---------- 平板分字段系数（平板相对手机的比率，<1 更收敛） ----------
  /// 平板对手机「提气强度」的系数
  static const double _tabletVibrancyRatio = 0.75;

  /// 平板对手机「渐变偏移」的系数（作用于顶部/底部偏移的绝对值）
  static const double _tabletGradientRatio = 0.8;

  /// 平板对手机「卡片透明度」的系数（1 对应手机的全实）
  static const double _tabletOpacityRatio = 0.85;

  /// 平板默认档：由手机基准 × 分字段系数推导。平板已用「白底+光晕」背景，整体较亮，
  /// 故提气、渐变、卡面透明度都按系数收敛，避免过亮与死白。
  static const PageVibrancyConfig tabletDefault = PageVibrancyConfig(
    vibrancy: 1.6 * _tabletVibrancyRatio,
    topShift: 0.05 * _tabletGradientRatio,
    bottomShift: -0.05 * _tabletGradientRatio,
    cardOpacity: 1.0 * _tabletOpacityRatio,
  );
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

  /// 今日学习计划（首页「学习」Tab）：顶底差小、整体明亮、卡片清晰；卡片更实更明亮
  static const PageVibrancyConfig todayPlan =PageVibrancyConfig.phoneDefault;

  /// 词表（首页「词表」Tab）
  static const PageVibrancyConfig wordLists = PageVibrancyConfig.phoneDefault;

  /// 查词（首页「查词」Tab）
  static const PageVibrancyConfig search = PageVibrancyConfig.phoneDefault;

  /// 我（首页「我」Tab）
  static const PageVibrancyConfig me = PageVibrancyConfig.phoneDefault;

  /// 学习统计
  static const PageVibrancyConfig studyStats = PageVibrancyConfig.phoneDefault;

  /// 记忆分布 / 复习分布
  static const PageVibrancyConfig reviewDistribution = PageVibrancyConfig.phoneDefault;

  /// 消息
  static const PageVibrancyConfig message = PageVibrancyConfig.phoneDefault;

  /// 单词详情
  static const PageVibrancyConfig wordDetail = PageVibrancyConfig.phoneDefault;

  /// 选词书
  static const PageVibrancyConfig selectBook = PageVibrancyConfig.phoneDefault;

  /// 完成页
  static const PageVibrancyConfig finish = PageVibrancyConfig.phoneDefault;

  /// 农场
  static const PageVibrancyConfig farm = PageVibrancyConfig.phoneDefault;

  /// 徽章墙
  static const PageVibrancyConfig badgeWall = PageVibrancyConfig.phoneDefault;

  /// 游戏大厅
  static const PageVibrancyConfig game = PageVibrancyConfig.phoneDefault;

  /// 随身听
  static const PageVibrancyConfig walkman = PageVibrancyConfig.phoneDefault;

  /// 等级路径
  static const PageVibrancyConfig levelPath = PageVibrancyConfig.phoneDefault;

  /// 提醒设置
  static const PageVibrancyConfig reminderSettings = PageVibrancyConfig.phoneDefault;
}
