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
}
