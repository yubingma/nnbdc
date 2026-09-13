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

/// 今日计划页"今日已打卡"印章的回归测试。
///
/// 已打卡时：目标环中心的"目标已锁定"换成微微倾斜的"今日已打卡"（环变印章），
/// 未打卡时：环心仍是"目标已锁定"，不得出现印章文案。
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
    // 无网络：同步与词书下载静默跳过
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

  /// 造一个"今日计划已学完"的账号：[dakaed] 决定今天是否已有打卡记录，
  /// [pendingExtraWords] > 0 表示打卡后追加的加量批次还没学完。
  Future<void> seedTodayPlan({
    required bool dakaed,
    int extraWords = 0,
    int extraDone = 0,
  }) async {
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
      dakaDayCount: 1,
      masteredWordsCount: 0,
      maxContinuousDakaDayCount: 1,
      continuousDakaDayCount: 1,
      todayStudyStarted: true,
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

    if (dakaed) {
      await db.dakasDao.saveDaka(
        Daka(
          userId: userId,
          forLearningDate: AppClock.today(),
          textContent: '好好学习，天天向上',
          createTime: now,
          updateTime: now,
        ),
        false,
      );
    }

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

    Future<void> addLearningWord(String wordId, int batchId, bool isExtra, int learnedTimes) {
      return db.into(db.learningWords).insert(LearningWord(
            userId: userId,
            wordId: wordId,
            addTime: now,
            addDay: 1,
            batchId: batchId,
            stability: 0.0,
            isTodayNewWord: true,
            learnedTimes: learnedTimes,
            todayLearnedTimes: learnedTimes,
            lastLearningDate: now,
            learningOrder: 0,
            createTime: now,
            updateTime: now,
            isExtra: isExtra,
          ));
    }

    // 计划词今日已走完各自轨道（学到远超轨道的次数即视为今日已完成）
    for (int i = 1; i <= 5; i++) {
      await addLearningWord('word_$i', 1, false, 99);
    }
    // 加量的前 extraDone 个词已学完，其余还等着继续学
    for (int i = 1; i <= extraWords; i++) {
      await addLearningWord('word_${5 + i}', 2, true, i <= extraDone ? 99 : 0);
    }
  }

  Future<void> pumpTodayPlan(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: const MaterialApp(home: TodayPlanPage()),
      ),
    );
    await tester.pump(); // 首帧
    await tester.pump(Duration.zero);
  }

  Future<void> pumpUntil(WidgetTester tester, Finder finder, {int maxPumps = 400}) async {
    for (int i = 0; i < maxPumps && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('今日已打卡：环心盖上"今日已打卡"印章，并有未学完的加量批次时主按钮为"继续学习（加量）"',
      (tester) async {
    // 印面文字是逐字画出来的（不是 Text），断言走承载它的 Key 与语义标签
    final semantics = tester.ensureSemantics();
    final seal = find.byKey(const Key('today_plan_daka_seal_text'));
    final sealDate = find.byKey(const Key('today_plan_daka_seal_date'));
    final today = AppClock.today();
    final dateLabel = '${today.year}.${today.month.toString().padLeft(2, '0')}'
        '.${today.day.toString().padLeft(2, '0')}';

    await seedTodayPlan(dakaed: true, extraWords: 5, extraDone: 2);
    await pumpTodayPlan(tester);
    await pumpUntil(tester, seal);

    expect(seal, findsOneWidget, reason: '今天打过卡，环心要盖上印章');
    expect(tester.getSemantics(seal).label, '今日已打卡', reason: '印章上写的必须是"今日已打卡"');
    expect(sealDate, findsOneWidget, reason: '印章上要有年月日的日期');
    expect(tester.getSemantics(sealDate).label, dateLabel, reason: '日期要是今天（逻辑日期）');
    expect(find.text('目标已锁定'), findsNothing, reason: '印章态不再重复讲"目标已锁定"');
    expect(find.text('继续学习（加量）'), findsOneWidget,
        reason: '还有未学完的加量批次时，主按钮是继续学习，而不是让人以为要新增单词');
    expect(find.text('加量已完成 2 / 5 词'), findsOneWidget,
        reason: '卡片里要同时讲清加量的数量（2 / 5 词）');
    expect(find.text('40%'), findsOneWidget, reason: '以及加量自己的进度（40%）');

    semantics.dispose();
    await tester.pump(const Duration(seconds: 60)); // 放掉节流同步等后台任务
  });

  testWidgets('今日未打卡：环心维持"目标已锁定"，不得出现印章文案', (tester) async {
    await seedTodayPlan(dakaed: false);
    await pumpTodayPlan(tester);
    await pumpUntil(tester, find.text('目标已锁定'));

    expect(find.text('目标已锁定'), findsOneWidget);
    expect(find.byKey(const Key('today_plan_daka_seal_text')), findsNothing,
        reason: '还没打卡就不能盖已打卡的章');
    expect(find.byKey(const Key('today_plan_daka_seal_date')), findsNothing,
        reason: '还没打卡就没有盖章日期');
    expect(find.textContaining('加量已完成'), findsNothing,
        reason: '今天没有加量批次，就不该出现加量进度');

    await tester.pump(const Duration(seconds: 60));
  });
}
