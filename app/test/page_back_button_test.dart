import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/widget/page_back_button.dart';

/// 模拟「比赛 / 词表 / 查词」三个功能页共用的宿主写法：
/// 页面既可能内嵌在首页底栏（路由栈底），也可能被「我」页面的
/// 功能收纳入口 push 成独立路由；调用方按 canPop 决定是否放入返回箭头。
class _HostPage extends StatelessWidget {
  const _HostPage();

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      body: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canPop) const PageBackButton(color: Colors.black),
            const Text('功能页'),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('内嵌在首页底栏（路由栈底）时不出现返回箭头', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _HostPage()));

    expect(find.text('功能页'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
  });

  testWidgets('被 push 成独立路由时出现返回箭头，点击可退回上一页', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const _HostPage()),
                ),
                child: const Text('进入功能页'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('进入功能页'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(find.text('进入功能页'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
  });
}
