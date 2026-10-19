import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ListTile wrapped in Material with card decoration does not trigger DecoratedBox assert', (WidgetTester tester) async {
    // 构造测试环境，验证 Material + RoundedRectangleBorder 包裹 ListTile 避免 DecoratedBox 遮盖断言
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (sheetContext) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Material(
                          color: const Color(0x80FFFFFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: const BorderSide(color: Color(0x26000000)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.reply_rounded),
                                title: const Text('引用回复这条'),
                                onTap: () => Navigator.pop(sheetContext),
                              ),
                              ListTile(
                                leading: const Icon(Icons.delete_outline),
                                title: const Text('删除这条消息'),
                                onTap: () => Navigator.pop(sheetContext),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('打开操作菜单'),
              );
            },
          ),
        ),
      ),
    );

    // 点击打开底部菜单
    await tester.tap(find.text('打开操作菜单'));
    await tester.pumpAndSettle();

    // 确认菜单选项正常呈现，没有抛出 Flutter 框架断言异常
    expect(find.text('引用回复这条'), findsOneWidget);
    expect(find.text('删除这条消息'), findsOneWidget);

    // 点击引用回复并顺利关闭
    await tester.tap(find.text('引用回复这条'));
    await tester.pumpAndSettle();

    expect(find.text('引用回复这条'), findsNothing);
  });

  testWidgets('Old pattern with DecoratedBox(color) triggers FlutterError assert', (WidgetTester tester) async {
    // 捕获异常
    final List<FlutterErrorDetails> errors = [];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
    };

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              decoration: BoxDecoration(
                color: const Color(0x80FFFFFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x26000000)),
              ),
              child: ListTile(
                title: const Text('测试项'),
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(errors.any((e) => e.toString().contains('ListTile background color or ink splashes may be invisible')), isTrue);
    } finally {
      FlutterError.onError = oldOnError;
    }
  });
}
