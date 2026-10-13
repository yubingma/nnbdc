import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/model/nav_tab_config.dart';

void main() {
  group('NavTabKey 底部导航与收纳逻辑测试', () {
    test('默认情况下所有 Tab 全部在底栏展示（非游客）', () {
      final visible = NavTabKey.getVisibleTabs(isGuest: false, hiddenKeys: []);
      expect(visible.length, 5);
      expect(visible, [
        NavTabKey.study,
        NavTabKey.wordLists,
        NavTabKey.search,
        NavTabKey.game,
        NavTabKey.me,
      ]);

      final stashed = NavTabKey.getStashedTabs(isGuest: false, hiddenKeys: []);
      expect(stashed.isEmpty, isTrue);
    });

    test('游客模式下比赛 Tab 自动过滤', () {
      final visible = NavTabKey.getVisibleTabs(isGuest: true, hiddenKeys: []);
      expect(visible.contains(NavTabKey.game), isFalse);
      expect(visible.length, 4);

      final stashed = NavTabKey.getStashedTabs(isGuest: true, hiddenKeys: ['game']);
      expect(stashed.contains(NavTabKey.game), isFalse);
    });

    test('用户隐藏「比赛」后，底栏移除比赛并进入收纳列表', () {
      final visible = NavTabKey.getVisibleTabs(isGuest: false, hiddenKeys: ['game']);
      expect(visible.length, 4);
      expect(visible.contains(NavTabKey.game), isFalse);

      final stashed = NavTabKey.getStashedTabs(isGuest: false, hiddenKeys: ['game']);
      expect(stashed.length, 1);
      expect(stashed.first, NavTabKey.game);
    });

    test('用户同时隐藏「比赛」和「查词」', () {
      final visible = NavTabKey.getVisibleTabs(
        isGuest: false,
        hiddenKeys: ['game', 'search'],
      );
      expect(visible.length, 3);
      expect(visible, [
        NavTabKey.study,
        NavTabKey.wordLists,
        NavTabKey.me,
      ]);

      final stashed = NavTabKey.getStashedTabs(
        isGuest: false,
        hiddenKeys: ['game', 'search'],
      );
      expect(stashed.length, 2);
      expect(stashed, [NavTabKey.search, NavTabKey.game]);
    });

    test('即使 hiddenKeys 包含不可隐藏的 study 和 me，底栏仍保持常驻兜底', () {
      final visible = NavTabKey.getVisibleTabs(
        isGuest: false,
        hiddenKeys: ['study', 'me', 'word_lists', 'search', 'game'],
      );
      // study 和 me 不允许被隐藏，且保证最少有它们存在
      expect(visible.contains(NavTabKey.study), isTrue);
      expect(visible.contains(NavTabKey.me), isTrue);
      expect(visible.length, 2);
    });

    test('旧版整数索引映射自洽且向后兼容', () {
      expect(NavTabKey.fromLegacyIndex(0), NavTabKey.study);
      expect(NavTabKey.fromLegacyIndex(1), NavTabKey.wordLists);
      expect(NavTabKey.fromLegacyIndex(2), NavTabKey.search);
      expect(NavTabKey.fromLegacyIndex(3), NavTabKey.game);
      expect(NavTabKey.fromLegacyIndex(4), NavTabKey.me);
      expect(NavTabKey.fromLegacyIndex(99), NavTabKey.me);
    });
  });

  group('NavBarShortcut 底栏唤起型入口测试', () {
    test('默认一个都不在底栏：随身听先住在快捷功能收纳里', () {
      final enabled = NavBarShortcut.getEnabled(isGuest: false, enabledKeys: []);
      expect(enabled, isEmpty);
    });

    test('用户打开开关后，随身听进入底栏', () {
      final enabled = NavBarShortcut.getEnabled(isGuest: false, enabledKeys: ['walkman']);
      expect(enabled, [NavBarShortcut.walkman]);
    });

    test('游客既选不了也留不住随身听（它要登录才能听）', () {
      expect(NavBarShortcut.getSelectable(isGuest: true), isEmpty);
      expect(NavTabKey.getCustomizable(isGuest: true).contains(NavTabKey.game), isFalse);

      // 先登录开了开关、又退出登录时，底栏不能再挂着一个点了只弹提示的图标
      final enabled = NavBarShortcut.getEnabled(isGuest: true, enabledKeys: ['walkman']);
      expect(enabled, isEmpty);
    });

    test('随身听紧挨「我」的左边，「我」永远在最右端', () {
      final ordered = NavBarItem.ordered(
        tabs: NavTabKey.getVisibleTabs(isGuest: false, hiddenKeys: []),
        shortcuts: NavBarShortcut.getEnabled(isGuest: false, enabledKeys: ['walkman']),
      );
      expect(ordered.map((item) => item.label), ['学习', '词表', '查词', '比赛', '随身听', '我']);
    });

    test('定制列表与底栏同序：定制列表从上到下就是底栏从左到右', () {
      // 底栏与定制列表各排各的，随身听就会在底栏里待在「我」左边、
      // 在定制列表里掉到「我」下边，用户没法拿定制列表当底栏的镜像来读。
      final onNavBar = NavBarItem.ordered(
        tabs: NavTabKey.getVisibleTabs(isGuest: false, hiddenKeys: ['game']),
        shortcuts: NavBarShortcut.getEnabled(isGuest: false, enabledKeys: ['walkman']),
      ).map((item) => item.label).toList();

      final inSheet = NavBarItem.ordered(
        tabs: NavTabKey.getCustomizable(isGuest: false),
        shortcuts: NavBarShortcut.getSelectable(isGuest: false),
      ).map((item) => item.label).toList();

      // 定制列表是全集，底栏是它的子序列；共同项的相对次序必须一模一样
      expect(inSheet, ['学习', '词表', '查词', '比赛', '随身听', '我']);
      expect(onNavBar, ['学习', '词表', '查词', '随身听', '我']);
    });
  });
}
