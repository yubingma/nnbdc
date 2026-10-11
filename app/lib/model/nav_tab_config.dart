/// 底部导航栏 Tab 语义配置
///
/// 图标统一取自 Lucide（24 网格 / 2px 圆头笔宽，见 `assets/images/nav/`）。原先混用了
/// Material 的 filled 字形与 rounded 字形两套体系，5 枚图标墨迹覆盖率从 16% 到 45%
/// 不等，并排放在底栏里大小肉眼可见地不齐——换图标时务必继续沿用同一套。
enum NavTabKey {
  study(
    key: 'study',
    label: '学习',
    icon: 'assets/images/nav/graduation-cap.svg',
    canHide: false,
    routePath: '/index',
    description: '每日背词核心主页',
  ),
  wordLists(
    key: 'word_lists',
    label: '词表',
    icon: 'assets/images/nav/library-big.svg',
    canHide: true,
    routePath: '/word_lists',
    description: '词书进度与选书桌',
  ),
  search(
    key: 'search',
    label: '查词',
    icon: 'assets/images/nav/search.svg',
    canHide: true,
    routePath: '/search',
    description: '快速查词与权威词典',
  ),
  game(
    key: 'game',
    label: '比赛',
    icon: 'assets/images/nav/gamepad-2.svg',
    canHide: true,
    routePath: '/game',
    description: '排位对战与消除竞技',
  ),
  me(
    key: 'me',
    label: '我',
    icon: 'assets/images/nav/circle-user.svg',
    canHide: false,
    routePath: '/index',
    description: '个人中心与功能收纳',
  );

  final String key;
  final String label;

  /// 图标的 SVG 资源路径。
  final String icon;

  final bool canHide;
  final String routePath;
  final String description;

  const NavTabKey({
    required this.key,
    required this.label,
    required this.icon,
    required this.canHide,
    required this.routePath,
    required this.description,
  });

  /// 从字符串 key 解析
  static NavTabKey? fromKey(String key) {
    for (final tab in NavTabKey.values) {
      if (tab.key == key) return tab;
    }
    return null;
  }

  /// 兼容旧式整数索引（0:学习, 1:词表, 2:查词, 3:比赛, 4:我）
  static NavTabKey fromLegacyIndex(int index) {
    switch (index) {
      case 0:
        return NavTabKey.study;
      case 1:
        return NavTabKey.wordLists;
      case 2:
        return NavTabKey.search;
      case 3:
        return NavTabKey.game;
      case 4:
      default:
        return NavTabKey.me;
    }
  }

  /// 获取当前应该在底栏展示的 Tab 列表
  static List<NavTabKey> getVisibleTabs({
    required bool isGuest,
    required List<String> hiddenKeys,
  }) {
    final list = <NavTabKey>[];
    for (final tab in NavTabKey.values) {
      // 游客模式不展示比赛
      if (isGuest && tab == NavTabKey.game) continue;
      // 用户主动隐藏且该项允许隐藏
      if (tab.canHide && hiddenKeys.contains(tab.key)) continue;
      list.add(tab);
    }
    // 安全兜底：无论如何，至少保留 study 和 me
    if (!list.contains(NavTabKey.study)) list.insert(0, NavTabKey.study);
    if (!list.contains(NavTabKey.me)) list.add(NavTabKey.me);
    return list;
  }

  /// 获取当前被用户收纳（移出底栏）的 Tab 列表
  static List<NavTabKey> getStashedTabs({
    required bool isGuest,
    required List<String> hiddenKeys,
  }) {
    final list = <NavTabKey>[];
    for (final tab in NavTabKey.values) {
      if (!tab.canHide) continue;
      if (isGuest && tab == NavTabKey.game) continue;
      if (hiddenKeys.contains(tab.key)) {
        list.add(tab);
      }
    }
    return list;
  }
}
