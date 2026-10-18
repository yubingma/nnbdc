import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/today_plan.dart';
import 'package:nnbdc/page/study_plan_settings.dart';
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

  Future<void> seedUser({required bool todayStudyStarted, int wordsPerDay = 5}) async {
    const String userId = 'test_lock_user';
    final user = User(
      id: userId,
      userName: 'lock_tester',
      password: '',
      nickName: 'LockTester',
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
      wordsPerDay: wordsPerDay,
      dakaDayCount: 1,
      masteredWordsCount: 0,
      maxContinuousDakaDayCount: 1,
      continuousDakaDayCount: 1,
      todayStudyStarted: todayStudyStarted,
      lastLearningDate: now,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      createTime: now,
      updateTime: now,
      studyConfig: '{"batchSize":5,"minNewWordsPerDay":0}',
    );
    await db.usersDao.saveUser(user, false);
    Global.currentUserId = userId;
    Global.updateUserCache(user);
    await Prefs.write('currentUserId', userId);

    const dictId = 'mock_dict_1';
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
    for (int i = 1; i <= 5; i++) {
      final wordId = 'word_$i';
      await db.into(db.words).insert(Word(
            id: wordId,
            spell: 'word_$i',
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
      await db.into(db.learningWords).insert(LearningWord(
            userId: userId,
            wordId: wordId,
            addTime: now,
            addDay: 1,
            batchId: 1,
            stability: 0.0,
            isTodayNewWord: false,
            learnedTimes: 1,
            todayLearnedTimes: 1,
            lastLearningDate: now,
            learningOrder: i,
            createTime: now,
            updateTime: now,
            isExtra: false,
          ));
    }
  }

  testWidgets('今日学习已开始时：顶部单词数显示小锁且不报词书单词量不足', (tester) async {
    await seedUser(todayStudyStarted: true, wordsPerDay: 50);

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: const MaterialApp(
          home: TodayPlanPage(),
        ),
      ),
    );

    for (int i = 0; i < 400 && find.text('今日 5 词').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 1. 顶部文案应为今日计划词数（今日 5 词），而不是与 50 比较的 5 / 50
    expect(find.text('今日 5 词'), findsOneWidget);
    expect(find.text('今日 5 / 50 词'), findsNothing);

    // 2. 顶部带有小锁图标
    expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);

    // 3. 不应出现误报的“词书单词量不足”警告
    expect(find.text('词书单词量不足'), findsNothing);

    // 消耗防抖同步的 pending timer (200ms)
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('今日学习已开始时：学习计划设置页进入锁定态且不保存修改', (tester) async {
    await seedUser(todayStudyStarted: true, wordsPerDay: 5);

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: const MaterialApp(
          home: StudyPlanSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 存在顶部锁定提示
    expect(find.text('今日学习已开始，设置已锁定'), findsOneWidget);

    // 2. 三个卡片展示锁定的 badgeText
    expect(find.text('5 词'), findsOneWidget);
    expect(find.text('不限制'), findsOneWidget);
    expect(find.text('5 词/组'), findsOneWidget);

    // 3. 不显示调节步进器
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byIcon(Icons.remove_rounded), findsNothing);
  });
}
