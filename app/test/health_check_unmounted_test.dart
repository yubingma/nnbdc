import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/admin/health_check.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/data_integrity_checker.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  final now = AppClock.now();
  const userId = '87da98b4b86848f082d65d138c988abc';

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    Global.clearUserCache();

    await db.into(db.users).insert(User(
          id: userId,
          userName: 'test_user',
          password: '',
          nickName: 'Tester',
          email: '',
          gameScore: 0,
          dakaScore: 0,
          learnedDays: 0,
          learningFinished: false,
          inviteAwardTaken: false,
          isSuperAdmin: false,
          isAdmin: false,
          isInputor: true,
          cowDung: 0,
          throwDiceChance: 0,
          wordsPerDay: 5,
          dakaDayCount: 0,
          masteredWordsCount: 0,
          maxContinuousDakaDayCount: 0,
          continuousDakaDayCount: 0,
          todayStudyStarted: false,
          totalLearningSeconds: 0,
          todayLearningSeconds: 0,
          createTime: now,
          updateTime: now,
        ));
    SharedPreferences.setMockInitialValues({
      'currentUserId': userId,
    });
    await Prefs.init();
    await Global.loadUserFromDb();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('健康检查在异步诊断中 unmount 不会触发 setState 崩溃', (tester) async {
    // 渲染带有 HealthCheckPage 的容器
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: const ToastificationWrapper(
          child: MaterialApp(
            home: HealthCheckPage(autoStart: true),
          ),
        ),
      ),
    );

    // 触发第一帧启动异步诊断
    await tester.pump();

    // 模拟用户在异步诊断还在进行时退出了页面（即 unmount 该 Widget）
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: const ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(body: Text('已退出')),
          ),
        ),
      ),
    );

    // 推进时间让后台未完成的 delayed 触发完毕，确认无未捕获异常抛出
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('已退出'), findsOneWidget);
  });

  testWidgets('健康检查在自动修复中 unmount 不会触发 setState 崩溃', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: ToastificationWrapper(
          child: MaterialApp(
            home: HealthCheckPage(key: key),
          ),
        ),
      ),
    );
    await tester.pump();

    final state = key.currentState as dynamic;
    final dummyResult = IntegrityCheckResult();
    dummyResult.addIssue('测试问题', '测试问题描述', 'dict_word_sequence');

    // 启动自动修复 Future
    final fixFuture = state.runAutoFixForTesting(dummyResult);

    // 模拟用户在修复执行期间退出页面（即 unmount 该 Widget）
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: const ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(body: Text('已退出')),
          ),
        ),
      ),
    );

    // 等待修复任务完成，断言不会抛出 Null check operator used on a null value
    await fixFuture;
    await tester.pumpAndSettle();
    expect(find.text('已退出'), findsOneWidget);
  });
}
