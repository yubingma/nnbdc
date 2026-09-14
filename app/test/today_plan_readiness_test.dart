import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/today_plan.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 今日计划页的"就绪门禁"回归测试。
///
/// 背景：跨天时本日计划（跨天重置 + 取词）还没完成，而页面第 1 步本地加载完就会渲染出
/// "开始学习"入口；用户此时点击，会把昨天残留的进度当成"今日已完成"而被直接送去打卡页。
/// 因此页面必须在准备流程跑完之前保持"未就绪"。
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
    // 默认：无网络（同步静默跳过）
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
    ThrottledDbSyncService().reset();
    await db.close();
    Global.currentUserId = null;
    Global.commonDictId = "0";
  });

  /// 造一个"昨天学过、今天还没学"的账号：用户行日期停在昨天，计划里 5 个词带着昨日的今日进度。
  /// [learningDateIsToday] 为 true 时把最近学习日改成今天，用于复现"今天就学过、本地也有计划词"的
  /// 同日刷新场景（此时页面会先渲染本地数据，而云端同步与取词仍在途）。
  Future<void> seedYesterdayPlan(String userId, {bool learningDateIsToday = false}) async {
    final yesterday = now.subtract(const Duration(days: 1));
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
      dakaDayCount: 1,
      masteredWordsCount: 0,
      maxContinuousDakaDayCount: 1,
      continuousDakaDayCount: 1,
      todayStudyStarted: true, // 昨天已开始学习
      lastLearningDate: learningDateIsToday ? now : yesterday, // 昨天 → 今天跨天；今天 → 同日刷新
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      createTime: now,
      updateTime: now,
    );
    await db.usersDao.saveUser(user, false);

    Global.currentUserId = userId;
    Global.updateUserCache(user);
    Prefs.write('currentUserId', userId);

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
            learnedTimes: 1,
            todayLearnedTimes: 2, // 新词轨道 [测评, List] 长 2 → 昨日已走完
            lastLearningDate: yesterday,
            learningOrder: i,
            createTime: now,
            updateTime: now,
            isExtra: false,
          ));
    }
  }

  /// 造一个"今天已开始学习、本地却没有任何计划数据"的账号：重装或换端后本地库为空，
  /// 但用户行日期已是今天，页面会先把空的 0/0 当成本地数据渲染出来。
  Future<void> seedEmptyTodayPlan(String userId) async {
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
      dakaDayCount: 1,
      masteredWordsCount: 0,
      maxContinuousDakaDayCount: 1,
      continuousDakaDayCount: 1,
      todayStudyStarted: false,
      lastLearningDate: now, // 最近学习日 = 今天 → 非跨天
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      createTime: now,
      updateTime: now,
    );
    await db.usersDao.saveUser(user, false);
    Global.currentUserId = userId;
    Global.updateUserCache(user);
    Prefs.write('currentUserId', userId);
  }

  Future<void> pumpTodayPlan(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: const MaterialApp(home: TodayPlanPage()),
      ),
    );
    await tester.pump(); // 首帧
    await tester.pump(Duration.zero); // 触发 didChangeDependencies 里的 Timer.run(loadData)
  }

  Future<void> pumpUntil(WidgetTester tester, Finder finder, {int maxPumps = 400}) async {
    for (int i = 0; i < maxPumps && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('跨天且今日计划仍在准备（阻塞式同步在途）时：页面不得给出"开始学习"入口', (tester) async {
    await seedYesterdayPlan('test_user_id');

    // 用"挂起的网络探测"卡住阻塞式云端同步，还原真实世界里那个长达数秒的准备窗口期
    final networkProbe = Completer<dynamic>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) => networkProbe.future,
    );

    await pumpTodayPlan(tester);
    await tester.pump(const Duration(milliseconds: 100)); // 让本地加载与跨天判定执行完

    expect(find.text('开始学习'), findsNothing,
        reason: '跨天时计划尚未就绪，页面不得给出开始学习入口（否则昨日残留进度会被当成今日已完成）');
    expect(find.byType(CircularProgressIndicator), findsWidgets, reason: '此时应呈现加载中');

    networkProbe.complete(<String>[]); // 放行，避免残留未完成的 Future
    await tester.pump(const Duration(seconds: 60)); // 放掉放行后恢复准备流程触发的节流同步等后台任务
  });

  testWidgets('跨天计划准备完成后：入口恢复，且昨日残留的今日进度已被跨天重置清零', (tester) async {
    await seedYesterdayPlan(Global.guestId); // 游客不触发云端同步，可观察到完整准备流程

    await pumpTodayPlan(tester);
    await pumpUntil(tester, find.text('开始学习'));

    expect(find.text('开始学习'), findsOneWidget, reason: '计划就绪后必须恢复入口');

    await tester.runAsync(() async {
      final words = await db.select(db.learningWords).get();
      expect(words.where((w) => w.todayLearnedTimes > 0).toList(), isEmpty,
          reason: '昨日残留进度必须随跨天重置清零，否则会被当成本日成绩');
    });

    await tester.pump(const Duration(seconds: 60)); // 放掉节流同步等后台任务
  });

  testWidgets('本地一份计划词都拿不到而准备仍在途时：页面不得呈现 0/0 的"就绪"假象', (tester) async {
    await seedEmptyTodayPlan('test_user_id');

    // 用"挂起的网络探测"卡住阻塞式云端同步，还原重装/换端后本地库为空、
    // 计划数据还在云端的那段窗口期
    final networkProbe = Completer<dynamic>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) => networkProbe.future,
    );

    await pumpTodayPlan(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('开始学习'), findsNothing,
        reason: '本地没有计划词时 0/0 只是假象，不得给出开始学习入口');
    expect(find.byType(CircularProgressIndicator), findsWidgets, reason: '此时应呈现加载中');

    networkProbe.complete(<String>[]); // 放行，避免残留未完成的 Future
    await tester.pump(const Duration(seconds: 60)); // 放掉放行后恢复准备流程触发的节流同步等后台任务
  });

  testWidgets('本地已有今日计划词时：页面先渲染入口，不被准备流程挡住', (tester) async {
    await seedYesterdayPlan('test_user_id', learningDateIsToday: true);

    await pumpTodayPlan(tester);
    await pumpUntil(tester, find.text('开始学习'));

    expect(find.text('开始学习'), findsOneWidget, reason: '本地已有今日计划词，必须先把页面渲染出来');
    expect(find.text('LOADING PLAN'), findsNothing, reason: '不得因为云端同步在途而把页面挡在加载态');

    await tester.pump(const Duration(seconds: 60)); // 放掉节流同步等后台任务
  });
}
