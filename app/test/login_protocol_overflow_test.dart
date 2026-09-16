import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/login.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('login_test_');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => <String>[],
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('fluwx'),
      (MethodCall methodCall) async => false,
    );
  });

  tearDownAll(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  testWidgets('登录页协议行在窄屏与大字号下不溢出且自适应折行', (tester) async {
    // 模拟 320dp 极窄屏手机
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
        child: MaterialApp(
          theme: ThemeData(
            // 模拟大字号缩放 (1.3x)
            textTheme: const TextTheme(
              bodyMedium: TextStyle(fontSize: 16),
            ),
          ),
          home: const LoginPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 验证没有抛出 RenderFlex 溢出异常
    expect(tester.takeException(), isNull);

    // 验证协议文本和链接正常展示
    expect(find.textContaining('同意'), findsOneWidget);
    expect(find.text('《用户协议》'), findsOneWidget);
    expect(find.text('《隐私政策》'), findsOneWidget);
  });
}
