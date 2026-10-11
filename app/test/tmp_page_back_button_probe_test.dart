import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/widget/page_back_button.dart';

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/index',
    routes: [
      GoRoute(
        path: '/index',
        builder: (context, state) => Scaffold(
          body: Center(child: PageBackButton(color: Colors.black)),
        ),
      ),
      GoRoute(
        path: '/russia',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('对局页'))),
      ),
    ],
  );
}

void main() {
  testWidgets('栈里只剩一层时点返回箭头，导航栈被弹空', (tester) async {
    final router = _buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // 模拟：从大厅进入对局页，再返回大厅
    router.push('/russia');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.matches.length, 2);

    router.pop();
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.matches.length, 1);

    // 此刻栈里只剩 /index 一层，界面上仍有返回箭头（canPop 是上一次 build 时算出来的）
    final canPopNow = router.routerDelegate.canPop();
    debugPrint('>>> 弹回大厅后 canPop = $canPopNow');

    // 点这个返回箭头
    await tester.tap(find.byType(PageBackButton));
    await tester.pumpAndSettle();

    debugPrint(
        '>>> 点击后 matches 数量 = ${router.routerDelegate.currentConfiguration.matches.length}');
    debugPrint('>>> 界面是否只剩空盒子: ${find.text('对局页').evaluate().isEmpty}');
  });
}
