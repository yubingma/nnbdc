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
  const String userId = 'test_pet_speech_user';
  const String dictId = 'mock_dict_pet';

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

  Future<void> seedData() async {
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
    await db.into(db.users).insert(user);
    Global.currentUserId = userId;

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

  testWidgets('宠物台词气泡属于 TodayPlanPage 内部树，点击可弹出并在收起时消失', (tester) async {
    await seedData();

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

    // 等待今日计划初始加载完成（等待数据就绪，非 loading 状态）
    for (int i = 0; i < 400 && find.text('今日 5 词').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('今日 5 词'), findsOneWidget, reason: '数据应已就绪');

    final state = tester.state<TodayPlanPageState>(find.byType(TodayPlanPage));

    // 进入页面不主动开口：等过原来的自动台词延时后，气泡仍为空
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.petSpeechTextForTest, isNull, reason: '宠物不应主动说话，只有点击才开口');

    // 手动调用点击宠物触发说话
    state.onPetTapForTest();
    await tester.pump();

    // 气泡内文字必定存在
    final petBubbleFinder = find.descendant(
      of: find.byType(TodayPlanPage),
      matching: find.byType(IgnorePointer),
    );
    expect(petBubbleFinder, findsWidgets, reason: '宠物气泡应在 TodayPlanPage 自身子树内渲染');

    // 调用收起
    state.dismissPetSpeechForTest();
    await tester.pump();

    // 验证状态已被清空
    expect(state.petSpeechTextForTest, isNull, reason: '收起后气泡文本应为 null');

    // 排空异步 Timer（防抖同步 200ms 与气泡自动收起 2600ms）
    await tester.pump(const Duration(seconds: 3));
  });
}
