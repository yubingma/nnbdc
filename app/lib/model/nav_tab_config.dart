/// 底部导航栏配置
///
/// 底栏上从左到右的每个位置都是一个 [NavBarItem]，分两类：
/// - **切页型** [NavTabKey]：选中后就停在那一页，是页面容器里的一页；
/// - **唤起型** [NavBarShortcut]：点开就推一个独立全屏页，没有选中态。
///
/// 图标统一取自 Lucide（24 网格 / 2px 圆头笔宽，见 `assets/images/nav/`）。原先混用了
/// Material 的 filled 字形与 rounded 字形两套体系，图标墨迹覆盖率从 16% 到 45%
/// 不等，并排放在底栏里大小肉眼可见地不齐——换图标时务必继续沿用同一套。
sealed class NavBarItem {
  String get key;
  String get label;

  /// 图标的 SVG 资源路径。
  String get icon;

  String get description;

  /// 底栏从左到右的项次序：唤起型入口紧挨「我」的左边，「我」永远在最右端。
  ///
  /// 底栏自己与「底栏导航定制」列表都按它排——定制列表从上到下就是底栏从左到右，
  /// 用户才能拿定制列表当底栏的镜像来读。[tabs] 是要排的切页型项：底栏传当前
  /// 可见的那些，定制列表传当前可定制的那些。
  static List<NavBarItem> ordered({
    required List<NavTabKey> tabs,
    required List<NavBarShortcut> shortcuts,
  }) {
    final items = <NavBarItem>[];
    for (final tab in tabs) {
      if (tab == NavTabKey.me) items.addAll(shortcuts);
      items.add(tab);
    }
    return items;
  }
}

enum NavTabKey implements NavBarItem {
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

  /// 当前用户可以定制的切页型 Tab：游客没有比赛（它要登录）
  static List<NavTabKey> getCustomizable({required bool isGuest}) {
    return values
        .where((tab) => !(isGuest && tab == NavTabKey.game))
        .toList();
  }

  /// 获取当前应该在底栏展示的 Tab 列表
  static List<NavTabKey> getVisibleTabs({
    required bool isGuest,
    required List<String> hiddenKeys,
  }) {
    // 用户主动隐藏且该项允许隐藏的，移出底栏
    final list = getCustomizable(isGuest: isGuest)
        .where((tab) => !(tab.canHide && hiddenKeys.contains(tab.key)))
        .toList();
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
    return getCustomizable(isGuest: isGuest)
        .where((tab) => tab.canHide && hiddenKeys.contains(tab.key))
        .toList();
  }
}

/// 底栏上「点开即走」的唤起型入口。
///
/// 与 [NavTabKey] 是两类东西：NavTabKey 是常驻页面，选中后就停在那一页、
/// 底栏图标有选中态，页面容器也按它的顺序建页；唤起型入口只是底栏上的一枚
/// 图标，点开就推一个独立全屏页（随身听是全屏沉浸页），返回后底栏仍停在
/// 原来那一页，因此它既不参与底栏下标计算，也不进页面容器。
///
/// 默认一个都不在底栏——它们本就住在「快捷功能收纳」里，想让它常驻的人
/// 自己去「底栏导航管理」打开。
enum NavBarShortcut {
  walkman(
    key: 'walkman',
    label: '随身听',
    icon: 'assets/images/nav/headphones.svg',
    description: '不用看屏幕，随时接着听',
  );

  final String key;
  final String label;

  /// 图标的 SVG 资源路径，与 [NavTabKey] 同一套（24 网格 / 2px 圆头笔宽）。
  final String icon;

  final String description;

  const NavBarShortcut({
    required this.key,
    required this.label,
    required this.icon,
    required this.description,
  });

  /// 当前用户可选的唤起型入口。游客听不了随身听（要登录），所以选不了它。
  static List<NavBarShortcut> getSelectable({required bool isGuest}) {
    return values
        .where((shortcut) => !(isGuest && shortcut == NavBarShortcut.walkman))
        .toList();
  }

  /// 获取当前已经放进底栏的唤起型入口
  static List<NavBarShortcut> getEnabled({
    required bool isGuest,
    required List<String> enabledKeys,
  }) {
    return getSelectable(isGuest: isGuest)
        .where((shortcut) => enabledKeys.contains(shortcut.key))
        .toList();
  }
}
