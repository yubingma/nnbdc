import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/review_distribution.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;

  setUpAll(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => <String>[],
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Global.currentUserId = 'test_user_1';
  });

  tearDown(() async {
    await db.close();
    Global.currentUserId = null;
  });

  testWidgets('复习分布说明弹窗在窄屏约束下不溢出且渲染毛玻璃', (tester) async {
    // 模拟超窄屏手机（320dp 宽度，对应极狭窄标题约束）
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final darkMode = DarkMode();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DarkMode>.value(value: darkMode),
        ],
        child: const MaterialApp(
          home: ReviewDistributionPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 验证 AppBar 上已无冗余的问号图标
    expect(find.byIcon(Icons.help_outline_rounded), findsNothing);

    // 点击卡片上的「图表说明」打开说明弹窗
    final explainButton = find.text('图表说明');
    expect(explainButton, findsOneWidget);
    await tester.tap(explainButton);
    await tester.pumpAndSettle();

    // 验证没有发生 RenderFlex 溢出
    expect(tester.takeException(), isNull);

    // 验证弹窗成功弹出，包含标题与 BackdropFilter 毛玻璃
    expect(find.text('FSRS 自适应记忆算法'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsWidgets);

    // 点击“我知道了”关闭弹窗
    final closeBtn = find.text('我知道了');
    expect(closeBtn, findsOneWidget);
    await tester.tap(closeBtn);
    await tester.pumpAndSettle();

    expect(find.text('FSRS 自适应记忆算法'), findsNothing);
  });
}
