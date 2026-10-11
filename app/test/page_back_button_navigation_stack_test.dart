import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/widget/page_back_button.dart';

/// 锁死 2026-10-11「首页底栏 · 比赛 → 对局 → 返回 → 再点返回」整屏空白的事故。
///
/// 事故物理：返回箭头的显隐由调用点在 build 时用 `Navigator.of(context).canPop()`
/// 算一次快照决定。路由栈变浅后页面不会重算，箭头就滞留在已经退无可退的页面上；
/// 点中它 → 原生 `Navigator.pop()` 把首页那一层壳也弹掉 → go_router 匹配栈清空 →
/// 只渲染一个空盒子，整屏只剩 main.dart 铺在最底层的全局背景。
///
/// 这里故意用「无条件摆放返回箭头」的宿主页面，模拟快照已经过期的那一刻：
/// 箭头该不该出现，只允许由组件自己按导航栈实时决定。
GoRouter _router() => GoRouter(
      initialLocation: '/index',
      routes: [
        GoRoute(
          path: '/index',
          builder: (context, state) => Scaffold(
            // 左上角只留给返回箭头（该出现时才出现），"匹配"沉到页面底部，
            // 这样在 (24,24) 上点下去要么命中箭头、要么什么也点不到。
            body: Stack(
              children: [
                const Positioned(
                  left: 0,
                  top: 0,
                  child: PageBackButton(
                    key: ValueKey('indexBack'),
                    color: Colors.black,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: TextButton(
                    onPressed: () => context.push('/russia'),
                    child: const Text('匹配'),
                  ),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/russia',
          builder: (context, state) => Scaffold(
            body: Stack(
              children: [
                const Positioned(
                  left: 0,
                  top: 0,
                  child: PageBackButton(
                    key: ValueKey('russiaBack'),
                    color: Colors.black,
                  ),
                ),
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Text('对局页'),
                ),
              ],
            ),
          ),
        ),
      ],
    );

/// 某个宿主页面上的返回箭头此刻是否真的画了出来。
Finder _arrowInside(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byIcon(Icons.arrow_back_ios_new_rounded),
    );

void main() {
  testWidgets('内嵌在首页底栏（导航栈只有一层）时不画返回箭头', (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.matches.length, 1);
    expect(_arrowInside('indexBack'), findsNothing);
  });

  testWidgets('从对局页退回首页后，首页不再残留返回箭头', (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('匹配'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.matches.length, 2);
    expect(_arrowInside('russiaBack'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('russiaBack')));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.matches.length, 1);
    expect(_arrowInside('indexBack'), findsNothing);
  });

  testWidgets('退无可退时再点原返回箭头的位置，不会把首页壳一起弹掉', (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('匹配'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('russiaBack')));
    await tester.pumpAndSettle();

    // 事故动作：在对局页返回大厅后，又在原位置点了一次"返回"
    await tester.tapAt(const Offset(24, 24));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.matches.length, 1);
    expect(find.text('匹配'), findsOneWidget);
  });
}
