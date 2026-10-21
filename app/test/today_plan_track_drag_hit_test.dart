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
import 'package:toastification/toastification.dart';

/// 今日计划「拖拽编排轨道」的落点回归测试。
///
/// 结构事实：拖拽的判定点由 Flutter 的 `_DragAvatar.updateDrag` 决定——
/// 它拿 `globalPosition + feedbackOffset` 去做 hitTest。所以 `feedbackOffset`
/// 一旦非零，手指就得让开那段位移才能命中放置条，胶囊一侧会变成死区。
/// 这个测试把手指停在放置条的左边缘附近：判定点必须跟手，落在胶囊里就该能放下。
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

  /// 造一个"今天还没开始学"的账号：词书 10 词，今日计划 5 词。
  Future<void> seedTodayPlanNotStarted() async {
    const String userId = 'test_user_id';
    final user = User(
      id: userId,
      userName: 'mock_user',
      password: '',
      nickName: 'Tester',
      email: '',
      gameScore: 0,
      dakaScore: 0,
      learnedDays: 1,
      learningFinished: false,
      inviteAwardTaken: false,
      isSuperAdmin: false,
      isAdmin: false,
      isInputor: false,
      cowDung: 0,
      throwDiceChance: 0,
      wordsPerDay: 5,
      dakaDayCount: 0,
      masteredWordsCount: 0,
      maxContinuousDakaDayCount: 0,
      continuousDakaDayCount: 0,
      todayStudyStarted: false,
      lastLearningDate: now,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      createTime: now,
      updateTime: now,
    );
    await db.usersDao.saveUser(user, false);
    Global.currentUserId = userId;
    Global.updateUserCache(user);
    await Prefs.write('currentUserId', userId);

    const dictId = 'mock_dict_1';
    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '四级核心词汇',
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
    for (int i = 1; i <= 10; i++) {
      final wordId = 'word_$i';
      await db.into(db.words).insert(Word(
            id: wordId,
            spell: 'apple_$i',
            popularity: 100,
            createTime: now,
            updateTime: now,
          ));
      await db.into(db.dictWords).insert(DictWord(
            dictId: dictId,
            wordId: wordId,
            seq: i,
            unit: 0,
            createTime: now,
            updateTime: now,
          ));
    }
    for (int i = 1; i <= 5; i++) {
      await db.into(db.learningWords).insert(LearningWord(
            userId: userId,
            wordId: 'word_$i',
            addTime: now,
            addDay: 1,
            batchId: 1,
            stability: 0.0,
            isTodayNewWord: true,
            learnedTimes: 0,
            todayLearnedTimes: 0,
            lastLearningDate: now,
            learningOrder: i,
            createTime: now,
            updateTime: now,
            isExtra: false,
          ));
    }
  }

  Future<void> pumpTodayPlan(WidgetTester tester) async {
    // 编辑态下轨道图 + 托盘要同时可见才拖得起来，用一块够高的屏幕。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: ToastificationWrapper(
          child: MaterialApp(
            home: const TodayPlanPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(Duration.zero);
  }

  Future<void> pumpUntil(WidgetTester tester, Finder finder, {int maxPumps = 400}) async {
    for (int i = 0; i < maxPumps && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 编辑态下所有放置条（DragTarget）：答对/答错两条支路各自的胶囊 + 底部托盘。
  ///
  /// `_TrackDragPayload` 是私有类型，测试只能按基类 `DragTarget` 认。
  final zones = find.byWidgetPredicate((w) => w is DragTarget);

  testWidgets('从托盘拖环节：手指落在放置条左边缘也能放下（判定点必须跟手）', (tester) async {
    await seedTodayPlanNotStarted();
    await pumpTodayPlan(tester);
    await pumpUntil(tester, find.text('学习轨道'));

    await tester.tap(find.text('学习轨道'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget, reason: '进入编辑态');

    // 默认轨道：新词/旧词的测评环节都是英译汉，托盘里另有一份「英译汉」卡片。
    expect(find.text('英译汉'), findsNWidgets(3), reason: '两条轨道的测评环节 + 托盘卡片');

    expect(zones, findsWidgets);
    final Rect zone = tester.getRect(zones.first);
    // 手指停在胶囊左边缘往里 8px。判定点若被 feedbackOffset 往左拉偏，
    // 这里就会落到胶囊外面，环节放不进去（用户反馈的"必须放到靠右才能感应"）。
    final Offset dropAt = Offset(zone.left + 8, zone.center.dy);

    final chip = find.text('英译汉').last;
    final gesture = await tester.startGesture(tester.getCenter(chip));
    await tester.pump(const Duration(milliseconds: 300)); // 越过 220ms 长按阈值
    await gesture.moveTo(dropAt);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('英译汉'), findsNWidgets(4),
        reason: '手指在胶囊左边缘松开，环节也要落进去（判定点 = 手指位置）');

    await tester.pump(const Duration(seconds: 60)); // 放掉节流同步等后台任务
  });
}
