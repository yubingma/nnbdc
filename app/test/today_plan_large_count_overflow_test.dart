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

/// 今日计划页「词量很大时会不会又溢出」的回归测试。
///
/// 背景：左卡一格只有半张卡宽（真机 360dp 下可用宽约 48dp），
/// 加量态「1000 + 200」这种长数字行曾把那一格撑爆（真机实测溢出 1.9px）。
/// 这里用**四位数计划 + 三位数加量**压在真机视口上，且分别在
/// 1.15 倍（这台真机的系统字号）与 2.0 倍（无障碍大字号）下守"不许溢出"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  final now = AppClock.now();

  const int planWords = 1000;
  const int extraWords = 200;

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

  /// 造一个"打卡后还有 200 个加量词没学"的重度账号：计划 1000 词、加量 200 词。
  Future<void> seedHeavyPlan() async {
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

    const dictId = 'mock_dict_1';
    final totalWords = planWords + extraWords;
    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '大词书',
          wordCount: totalWords,
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

    for (int i = 1; i <= totalWords; i++) {
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

    // 计划词今日都已学完（所以状态是"打卡后还没学完的加量批次"）
    for (int i = 1; i <= planWords; i++) {
      await addLearningWord('word_$i', 1, false, 99);
    }
    // 加量词一个都没学 → 数字行会渲染成「1000 + 200」
    for (int i = 1; i <= extraWords; i++) {
      await addLearningWord('word_${planWords + i}', 2, true, 0);
    }
  }

  Future<void> pumpTodayPlan(WidgetTester tester, {required double textScale}) async {
    // 真机（荣耀 KKG-AN00）：360dp 宽、系统字号 1.15 倍。
    // widget 测试默认 800dp 宽，半格富余得多，根本压不出问题。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const TodayPlanPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(Duration.zero);
    for (int i = 0; i < 300 && find.byKey(const Key('today_plan_extra_new_count')).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  for (final scale in <double>[1.15, 2.0]) {
    testWidgets('计划 1000 词 + 加量 200 词（字号 ${scale}x）：数字行不溢出', (tester) async {
      await seedHeavyPlan();
      await pumpTodayPlan(tester, textScale: scale);

      // 加量词按自己算新词还是旧词并进对应那张卡，两个键只会命中一个
      final extraTags = [
        find.byKey(const Key('today_plan_extra_new_count')),
        find.byKey(const Key('today_plan_extra_old_count')),
      ].where((f) => f.evaluate().isNotEmpty).toList();
      if (extraTags.isEmpty) {
        // 调试：把当前屏幕上的文案打出来，看清页面停在哪个状态
        // ignore: avoid_print
        print('SCREEN TEXTS: ' +
            tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).where((d) => d != null).join(' | '));
      }
      expect(extraTags, hasLength(1), reason: '加量态的数字行必须渲染出来（例如「1000 + 200」）');
      expect(tester.widget<Text>(extraTags.single).data, ' + 200');
      expect(tester.takeException(), isNull,
          reason: '${scale}x 字号下，四位计划数 + 三位加量数也不允许溢出');

      await tester.pump(const Duration(seconds: 60));
    });
  }
}
