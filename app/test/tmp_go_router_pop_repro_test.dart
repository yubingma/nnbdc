import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/widget/page_back_button.dart';

/// 模拟 IndexPage：长按底栏弹出功能收纳快捷菜单（真实实现见 nav_stash_widgets.dart:12-248）
class _IndexLike extends StatelessWidget {
  const _IndexLike();

  void _showStashMenu(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss_stashed_nav_menu',
      pageBuilder: (dialogCtx, a1, a2) {
        return Center(
          child: Material(
            child: InkWell(
              onTap: () {
                Navigator.pop(dialogCtx);
                context.push('/game');
              },
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Text('比赛'),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: GestureDetector(
          onLongPress: () => _showStashMenu(context),
          child: const Text('底栏'),
        ),
      ),
    );
  }
}

/// 模拟游戏大厅：既内嵌也可被 push
class _GameLike extends StatelessWidget {
  const _GameLike();

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      body: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canPop) const PageBackButton(color: Colors.black),
            const Text('单词PK大厅'),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('路径C：长按底栏 → 快捷菜单 → 点比赛 → 点返回', (tester) async {
    final router = GoRouter(
      initialLocation: '/index',
      routes: [
        GoRoute(path: '/index', builder: (c, s) => const _IndexLike()),
        GoRoute(path: '/game', builder: (c, s) => const _GameLike()),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    for (int round = 1; round <= 3; round++) {
      await tester.longPress(find.text('底栏'));
      await tester.pumpAndSettle();
      expect(find.text('比赛'), findsOneWidget, reason: '第$round轮菜单没弹出');

      await tester.tap(find.text('比赛'));
      await tester.pumpAndSettle();
      expect(find.text('单词PK大厅'), findsOneWidget, reason: '第$round轮没进大厅');
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget,
          reason: '第$round轮没有返回箭头');

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '第$round轮点返回崩溃');
      expect(find.text('底栏'), findsOneWidget, reason: '第$round轮没回到首页');
    }
  });
}
