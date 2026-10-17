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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  final now = AppClock.now();
  const String userId = 'test_words_change_user';
  const String dictId = 'mock_dict_1';

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
    Global.commonDictId = dictId;
  });

  tearDown(() async {
    toastification.dismissAll();
    await db.close();
    Global.currentUserId = null;
    Global.commonDictId = '0';
  });

  Future<void> seedData({bool todayStudyStarted = false, int initialWords = 5}) async {
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
      wordsPerDay: initialWords,
      dakaDayCount: 0,
      masteredWordsCount: 0,
      maxContinuousDakaDayCount: 0,
      continuousDakaDayCount: 0,
      todayStudyStarted: todayStudyStarted,
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

    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '测试词书',
          wordCount: 30,
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

    for (int i = 1; i <= 20; i++) {
      final wordId = 'w_$i';
      await db.into(db.words).insert(Word(
            id: wordId,
            spell: 'word$i',
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

    // 为当天先准备 initialWords 个词
    for (int i = 1; i <= initialWords; i++) {
      final wordId = 'w_$i';
      await db.into(db.learningWords).insert(LearningWord(
            userId: userId,
            wordId: wordId,
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

  testWidgets('今日未开始学习时，点击左上角今日单词数弹窗并选择新数量，页面今日单词数立即更新', (tester) async {
    await seedData(todayStudyStarted: false, initialWords: 5);

    await tester.pumpWidget(
      ToastificationWrapper(
        child: ChangeNotifierProvider<DarkMode>.value(
          value: DarkMode(),
          child: const MaterialApp(
            home: TodayPlanPage(),
          ),
        ),
      ),
    );

    // 等待今日计划加载完成
    for (int i = 0; i < 400 && find.text('今日 5 词').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('今日 5 词'), findsOneWidget, reason: '初始状态应显示今日 5 词');

    // 点击左上角今日单词数芯片
    await tester.tap(find.text('今日 5 词'));
    await tester.pumpAndSettle();

    expect(find.text('选择每日学习词数'), findsOneWidget, reason: '应弹出每日词数选择弹窗');

    // 点击 10 词选项（网格里有数字 10）
    final option10 = find.text('10');
    expect(option10, findsOneWidget);
    await tester.tap(option10);
    await tester.pump();

    // 等待 loadData 异步完成
    for (int i = 0; i < 400 && find.text('今日 10 词').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('今日 10 词'), findsOneWidget, reason: '修改后应立即生效并显示今日 10 词');

    final updatedUser = await db.usersDao.getUserById(userId);
    expect(updatedUser?.wordsPerDay, 10, reason: '数据库中用户的 wordsPerDay 应更新为 10');

    // 消费 Toast autoClose 定时器
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('今日已开始学习时，点击修改每日单词数，今日计划保持不变，提示明日生效', (tester) async {
    await seedData(todayStudyStarted: true, initialWords: 5);

    await tester.pumpWidget(
      ToastificationWrapper(
        child: ChangeNotifierProvider<DarkMode>.value(
          value: DarkMode(),
          child: const MaterialApp(
            home: TodayPlanPage(),
          ),
        ),
      ),
    );

    for (int i = 0; i < 400 && find.text('今日 5 词').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('今日 5 词'), findsOneWidget);

    await tester.tap(find.text('今日 5 词'));
    await tester.pumpAndSettle();

    final option10 = find.text('10');
    await tester.tap(option10);
    await tester.pumpAndSettle();

    // 今日已开始学习，今日词数保持为 5 词
    expect(find.text('今日 5 词'), findsOneWidget, reason: '已开始学习时今日词数当天不应改变');

    final updatedUser = await db.usersDao.getUserById(userId);
    expect(updatedUser?.wordsPerDay, 10, reason: '用户设置的 wordsPerDay 仍应被保存为 10（明日生效）');

    // 消费 Toast autoClose 定时器
    await tester.pump(const Duration(seconds: 4));
  });
}
