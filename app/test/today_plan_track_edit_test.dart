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
import 'package:nnbdc/page/study_track_settings.dart';

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

    for (int i = 0; i < 400 && find.byIcon(Icons.tune_rounded).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 点击右上角设置菜单入口展开高级设置弹窗
    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();
  }

  testWidgets('今日计划高级设置弹窗提供学习轨道设置与学习日期说明的独立导航入口', (tester) async {
    await seedUser();
    await pumpTodayPlan(tester);

    expect(find.text('学习轨道设置'), findsOneWidget, reason: '高级学习设置菜单应展示学习轨道设置入口');
    expect(find.text('学习日期说明'), findsOneWidget, reason: '高级学习设置菜单应展示学习日期说明入口');
    expect(find.text('新词测评'), findsNothing, reason: '主菜单弹窗内不应再内嵌冗长的轨道编辑，已抽离至二级页面');
  });

  testWidgets('学习轨道二级页面独立展示新词轨道与旧词轨道设置', (tester) async {
    await seedUser();

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: const MaterialApp(
          home: StudyTrackSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('学习轨道设置'), findsOneWidget);
    expect(find.text('新词轨道'), findsOneWidget);
    expect(find.text('旧词轨道'), findsOneWidget);
    expect(find.text('测评环节'), findsNWidgets(2), reason: '新词和旧词各有一个测评环节设置');
    expect(find.text('答对后环节'), findsNWidgets(2));
    expect(find.text('答错后环节'), findsNWidgets(2));
  });
}
