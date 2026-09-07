/// 页面级"提气强度"集中配置（全站唯一调整入口）
///
/// `vibrancy` 是 `AppThemeBackground` / `AppScaffold` 的提气强度：同一套主题，
/// 各页面可各自调节背景的通透鲜活程度。**数值越大越亮，无上限**，但因饱和度和
/// 明度被收紧到 [0,1]，背景到纯白即封顶；`0` 即当前默认观感。
///
/// 用法：页面在构造 `AppScaffold(vibrancy: ...)` 或 `AppThemeBackground(vibrancy: ...)`
/// 时引用这里的命名常量，而非手写数字。这样以后统一调整某个页面的提气档位，
/// 只需要改本文件，无需逐页改动业务逻辑。
class PageVibrancy {
  PageVibrancy._();

  // ========== 当前已生效的非零档位 ==========

  /// 启动/欢迎页（浅色模式下整页明亮、透出主题色氛围）
  static const double splash = 3;

  /// 登录页（与启动页一致的明亮通透氛围）
  static const double login = 3;

  // ========== 主要页面（默认 0 = 现状，需要时在此调高） ==========

  /// 今日学习计划（首页「学习」Tab）
  static const double todayPlan = 3;

  /// 词表（首页「词表」Tab）
  static const double wordLists = 0;

  /// 查词（首页「查词」Tab）
  static const double search = 0;

  /// 我（首页「我」Tab）
  static const double me = 0;

  /// 学习统计
  static const double studyStats = 0;

  /// 记忆分布 / 复习分布
  static const double reviewDistribution = 0;

  /// 消息
  static const double message = 0;

  /// 单词详情
  static const double wordDetail = 0;

  /// 选词书
  static const double selectBook = 0;

  /// 完成页
  static const double finish = 0;

  /// 农场
  static const double farm = 0;

  /// 徽章墙
  static const double badgeWall = 0;

  /// 游戏大厅
  static const double game = 0;

  /// 随身听
  static const double walkman = 0;

  /// 等级路径
  static const double levelPath = 0;

  /// 提醒设置
  static const double reminderSettings = 0;
}
