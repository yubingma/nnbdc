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
import 'package:nnbdc/util/study_config.dart';
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

  Future<void> seedUser({int wordsPerDay = 20, int batchSize = 10}) async {
    const String userId = 'test_batch_user';
    final user = User(
      id: userId,
      userName: 'batch_tester',
      password: '',
      nickName: 'BatchTester',
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
      todayStudyStarted: false,
      lastLearningDate: now,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      createTime: now,
      updateTime: now,
      studyConfig: '{"batchSize":$batchSize}',
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

  testWidgets('每组单词数：快捷标签固定为 5/10/20/30/50，支持点击弹窗直接输入 1~500 并持久化', (tester) async {
    // 用户的每日计划词数为 20
    await seedUser(wordsPerDay: 20, batchSize: 10);

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: const MaterialApp(
          home: TodayPlanPage(),
        ),
      ),
    );

    // 等待主页右上角高级设置图标就绪
    for (int i = 0; i < 400 && find.byIcon(Icons.tune_rounded).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byIcon(Icons.tune_rounded), findsWidgets);
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.tune_rounded).first));
    await tester.pumpAndSettle();

    // 验证高级学习设置弹窗打开
    expect(find.text('高级学习设置'), findsOneWidget);
    expect(find.text('每组单词数'), findsOneWidget);

    // 验证每组单词数的快捷药丸为经典 5 档：5, 10, 20, 30, 50（即使当日词数为 20）
    expect(find.text('50'), findsOneWidget, reason: '50词药丸应存在，不受当日词数20的限制');
    expect(find.text('200'), findsNothing, reason: '绝不应出现突兀的当日词数快捷标签');

    // 验证“今日最少新词”与“每组单词数”均具有对称的编辑小笔图标
    final editIcons = find.byIcon(Icons.edit_outlined);
    expect(editIcons, findsNWidgets(2), reason: '上下两个设置项均应展示对称统一的编辑小笔图标');
    await tester.tap(editIcons.last);
    await tester.pumpAndSettle();

    // 验证自定义弹窗已打开
    expect(find.text('自定义每组单词数'), findsOneWidget);
    expect(find.text('范围 1 ~ 500 词/组'), findsOneWidget);

    // 输入 200
    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);
    await tester.enterText(textField, '200');
    await tester.pump();

    // 点击确定
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 验证每组单词数已更新为 200（RichText 呈现）
    expect(
      find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('200 词/组')),
      findsOneWidget,
    );

    // 点击保存设置
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();

    // 验证持久化配置中的 batchSize 已更新为 200，且 effectiveBatchSize 为 200
    final savedConfig = StudyConfig.fromCurrentUser();
    expect(savedConfig.batchSize, 200);
    expect(savedConfig.effectiveBatchSize(20), 200, reason: '有效每组单词数已解耦，不再被当日计划截断');
  });
}
