import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/today_plan.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  final now = AppClock.now();

  setUpAll(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('nnbdc/ocr'),
      (MethodCall methodCall) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => <String>[],
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    StudyCacheManager().clear();
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Global.commonDictId = 'mock_dict_1';
  });

  tearDown(() async {
    await db.close();
    Global.currentUserId = null;
    Global.commonDictId = '0';
  });

  Future<void> seedUser() async {
    const userId = 'test_user_align';
    const dictId = 'mock_dict_1';
    Global.currentUserId = userId;

    final user = User(
      id: userId,
      wordsPerDay: 10,
      dakaDays: 0,
      dictId: dictId,
      lastSyncTime: now,
      createTime: now,
      updateTime: now,
    );
    await db.usersDao.saveUser(user, false);
    Global.updateUserCache(user);
    await Prefs.write('currentUserId', userId);

    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '测试词书',
          wordCount: 10,
          isShared: false,
          isReady: true,
          ownerId: 'sys',
          visible: true,
          editable: false,
          deletable: false,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.learningDicts).insert(LearningDict(
          userId: userId,
          dictId: dictId,
          isPrivileged: false,
          fetchMastered: false,
          sortAlg: 'ORIGINAL',
          createTime: now,
          updateTime: now,
        ));
  }

  testWidgets('平板宽屏下新词旧词区域与进度条的宽度严格等于250且左右边缘完全对齐', (tester) async {
    // 模拟 iPad 平板宽屏尺寸 (820 x 1180)
    tester.view.physicalSize = const Size(820, 1180);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await seedUser();

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: const MaterialApp(home: TodayPlanPage()),
      ),
    );
    await tester.pump();
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('新词'), findsOneWidget);
    expect(find.text('旧词'), findsOneWidget);

    // 找到包含新词和旧词的 Row
    final statRowFinder = find.ancestor(
      of: find.text('新词'),
      matching: find.byType(Row),
    ).first;

    // 找到包含 statRow 的 SizedBox
    final statSizedBoxFinder = find.ancestor(
      of: statRowFinder,
      matching: find.byType(SizedBox),
    ).first;

    final statRect = tester.getRect(statSizedBoxFinder);
    expect(statRect.width, 250.0, reason: '新词旧词区域宽度应为 250');

    // 找到进度条 LinearProgressIndicator 所在的容器
    final progressFinder = find.byType(LinearProgressIndicator);
    expect(progressFinder, findsOneWidget);

    final progressSizedBoxFinder = find.ancestor(
      of: progressFinder,
      matching: find.byType(SizedBox),
    ).first;

    final progressRect = tester.getRect(progressSizedBoxFinder);
    expect(progressRect.width, 250.0, reason: '进度条区域宽度应为 250');

    // 验证新词旧词与进度条在水平方向上的左边缘与右边缘完全严格对齐
    expect(statRect.left, equals(progressRect.left), reason: '新词旧词左边应与进度条左边对齐');
    expect(statRect.right, equals(progressRect.right), reason: '新词旧词右边应与进度条右边对齐');
  });
}
