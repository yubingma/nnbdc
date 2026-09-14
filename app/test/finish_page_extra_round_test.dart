import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/finish.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/services/user_privilege_manager.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 完成页"加量完成"判定的回归测试。
///
/// 背景：完成页曾拿"今日是否已打卡"当"本次学完的是不是加量批次"，
/// 于是打卡之后的任何一次正常学习（他端已打卡、调整单词量后补词再学）
/// 都会被讲成"加量完成"。判定必须回到"今日学习列表里是否真有加量词"。
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
    // 无网络：同步静默跳过
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
  });

  tearDown(() async {
    await db.close();
    Global.currentUserId = null;
  });

  /// 造一个"今天已经打过卡"的账号：
  /// [extraWords] > 0 表示今日学习列表里还有"再来一组"追加的加量词。
  Future<void> seedDakaedDay({int planWords = 5, int extraWords = 0}) async {
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
      wordsPerDay: planWords,
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

    int order = 0;
    Future<void> addWord(String wordId, int batchId, bool isExtra) {
      return db.into(db.learningWords).insert(LearningWord(
            userId: userId,
            wordId: wordId,
            addTime: now,
            addDay: 1,
            batchId: batchId,
            stability: 0.0,
            isTodayNewWord: true,
            learnedTimes: 1,
            todayLearnedTimes: 1,
            lastLearningDate: now,
            learningOrder: order++,
            createTime: now,
            updateTime: now,
            isExtra: isExtra,
          ));
    }

    for (int i = 1; i <= planWords; i++) {
      await addWord('plan_word_$i', 1, false);
    }
    for (int i = 1; i <= extraWords; i++) {
      await addWord('extra_word_$i', 2, true);
    }
  }

  Future<void> pumpFinish(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/finish',
      routes: [
        GoRoute(path: '/index', builder: (context, state) => const Scaffold()),
        GoRoute(path: '/finish', builder: (context, state) => const FinishPage()),
      ],
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    for (int i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('加量完成').evaluate().isNotEmpty ||
          find.text('打卡成功').evaluate().isNotEmpty) {
        return;
      }
    }
  }

  testWidgets('今日已打卡、今日没有加量词：完成页只讲"打卡成功"，不得讲"加量完成"', (tester) async {
    await seedDakaedDay();
    await pumpFinish(tester);

    expect(find.text('加量完成'), findsNothing,
        reason: '今日根本没追加过加量批次，正常学完不得被讲成"加量完成"');
    expect(find.text('打卡成功'), findsOneWidget);
    expect(find.text('打卡成果'), findsNothing,
        reason: '打卡已在今日首次结算，本次没有新的积分/魔法泡泡可展示');
  });

  testWidgets('今日已打卡、今日有加量词：完成页讲"加量完成"', (tester) async {
    await seedDakaedDay(extraWords: 3);
    await pumpFinish(tester);

    expect(find.text('加量完成'), findsOneWidget);
    expect(find.text('再来一组'), findsOneWidget);
  });

  testWidgets('从完成页点击加量学习(再来一组)进入学习页后，回退直接回到今日计划页(/index)而非再次进入完成页', (tester) async {
    const String userId = 'test_user_id';
    UserPrivilegeManager.isPremiumOverrideForTesting = true;
    addTearDown(() {
      UserPrivilegeManager.isPremiumOverrideForTesting = null;
    });

    await seedDakaedDay();

    // 种入激活词书和可用候选词，确保 prepareExtraStudy 成功
    final dictId = 'test_extra_dict';
    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '测试词书',
          wordCount: 10,
          isShared: false,
          isReady: true,
          ownerId: userId,
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
      final wid = 'extra_candidate_$i';
      await db.into(db.words).insert(Word(
            id: wid,
            spell: 'extra$i',
            popularity: 10,
            createTime: now,
            updateTime: now,
          ));
      await db.into(db.dictWords).insert(DictWord(
            dictId: dictId,
            wordId: wid,
            seq: i,
            unit: 0,
            createTime: now,
            updateTime: now,
          ));
    }

    String currentRoute = '/index';

    final router = GoRouter(
      initialLocation: '/index',
      routes: [
        GoRoute(
          path: '/index',
          builder: (context, state) {
            currentRoute = '/index';
            return const Scaffold(body: Text('今日学习计划'));
          },
        ),
        GoRoute(
          path: '/finish',
          builder: (context, state) {
            currentRoute = '/finish';
            return const FinishPage();
          },
        ),
        GoRoute(
          path: '/bdc',
          builder: (context, state) {
            currentRoute = '/bdc';
            return Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('退出背单词'),
              ),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ToastificationWrapper(
        child: ChangeNotifierProvider<DarkMode>.value(
          value: DarkMode(),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(currentRoute, '/index');

    // 模拟学完进入完成页（栈底为 /index，栈顶为 /finish）
    router.push('/finish');
    await tester.pumpAndSettle();
    for (int i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('再来一组').evaluate().isNotEmpty) break;
    }

    expect(find.text('再来一组'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/finish');

    // 点击"再来一组"，由于使用 pushReplacement，完成页应被 /bdc 替换
    await tester.tap(find.text('再来一组'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/bdc');
    expect(find.text('退出背单词'), findsOneWidget);

    // 在学习页点击回退(pop)，应直接回退到底部的今日计划页(/index)，而非完成页
    await tester.tap(find.text('退出背单词'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/index');
    expect(find.text('今日学习计划'), findsOneWidget);
    expect(find.text('打卡成功'), findsNothing);
    expect(find.text('加量完成'), findsNothing);
  });
}
