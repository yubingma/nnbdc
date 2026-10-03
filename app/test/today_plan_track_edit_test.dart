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

/// 今日计划页"学习轨道"调整入口的回归测试。
///
/// 每条轨道自带调整入口：点哪一行就只编辑那条轨道，编辑卡片里不得再出现需要来回切换的轨道 tab。
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
    const String userId = 'test_track_user';
    final user = User(
      id: userId,
      userName: 'track_tester',
      password: '',
      nickName: 'TrackTester',
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
      wordsPerDay: 20,
      dakaDayCount: 1,
      masteredWordsCount: 0,
      maxContinuousDakaDayCount: 1,
      continuousDakaDayCount: 1,
      todayStudyStarted: false,
      lastLearningDate: now,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      createTime: now,
      updateTime: now,
      studyConfig: '{"batchSize":10}',
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

  Future<void> pumpTodayPlan(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: const MaterialApp(
          home: TodayPlanPage(),
        ),
      ),
    );

    for (int i = 0; i < 400 && find.text('新词测评').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('新词测评'), findsOneWidget, reason: '今日计划页应已就绪并展示新词轨道');
  }

  testWidgets('每条轨道自带调整入口：点哪一行就只编辑那条轨道，无需切换轨道 tab', (tester) async {
    await seedUser();
    await pumpTodayPlan(tester);

    // 1. 点"旧词"那一行，必须直接进旧词轨道，且视线里不得出现新词轨道的任何入口
    await tester.ensureVisible(find.text('旧词测评'));
    await tester.tap(find.text('旧词测评'));
    await tester.pumpAndSettle();

    expect(find.text('旧词轨道'), findsOneWidget, reason: '编辑卡片应明示正在编辑旧词轨道');
    expect(find.text('新词轨道'), findsNothing, reason: '编辑旧词轨道时不得出现新词轨道，否则用户又要在两者之间切换');
    expect(find.text('完成'), findsOneWidget, reason: '编辑态应提供收起编辑的出口');

    // 2. 完成后点"新词"那一行，必须直接进新词轨道
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('新词测评'), findsOneWidget, reason: '完成后应回到两条轨道的显示态');

    await tester.ensureVisible(find.text('新词测评'));
    await tester.tap(find.text('新词测评'));
    await tester.pumpAndSettle();

    expect(find.text('新词轨道'), findsOneWidget, reason: '编辑卡片应明示正在编辑新词轨道');
    expect(find.text('旧词轨道'), findsNothing, reason: '编辑新词轨道时不得出现旧词轨道，否则用户又要在两者之间切换');
  });
}
