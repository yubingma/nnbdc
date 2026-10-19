import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/event/events.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/today_plan.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 今日计划页"已打卡"印章的回归测试。
///
/// 已打卡时：目标环中心换成微微倾斜的"已打卡"印章（下面跟当天日期），
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

  Future<void> pumpTodayPlan(WidgetTester tester, {double textScale = 1.0}) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: MaterialApp(
          // 真机（荣耀 KKG-AN00）系统字号是 1.15 倍：加量态的数字行正是在这个档位溢出过，
          // 所以溢出回归必须能在放大字号下复现，否则等于没守。
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const TodayPlanPage(),
        ),
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

  testWidgets('今日已打卡：环心盖上"已打卡"印章，并有未学完的加量批次时主按钮为"继续学习（加量）"',
      (tester) async {
    // 印面文字是逐字画出来的（不是 Text），断言走承载它的 Key 与语义标签
    final semantics = tester.ensureSemantics();
    final seal = find.byKey(const Key('today_plan_daka_seal_text'));
    final sealDate = find.byKey(const Key('today_plan_daka_seal_date'));
    final today = AppClock.today();
    // 日期串的单一来源：跟页面共用同一个格式化函数，杜绝"实现改了测试没跟上"
    final dateLabel = planIslandDateLabel(today);

    await seedTodayPlan(dakaed: true, extraWords: 5, extraDone: 2);
    await pumpTodayPlan(tester);
    // 学习轨道默认收起（只露新词 / 旧词两枚数字），打卡印章在展开后才出现
    await tester.tap(find.text('学习轨道'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, seal);

    expect(seal, findsOneWidget, reason: '今天打过卡，环心要盖上印章');
    expect(tester.getSemantics(seal).label, '已打卡', reason: '印章上写"已打卡"即可，日期就在下面');
    expect(sealDate, findsOneWidget, reason: '印章上要有年月日的日期');
    expect(tester.getSemantics(sealDate).label, dateLabel, reason: '日期要是今天（逻辑日期）');
    expect(find.text('目标已锁定'), findsNothing, reason: '印章态不再重复讲"目标已锁定"');
    expect(find.text('继续学习（加量）'), findsOneWidget,
        reason: '还有未学完的加量批次时，主按钮是继续学习，而不是让人以为要新增单词');
    expect(find.textContaining('加量已完成'), findsNothing,
        reason: '进度条彻底移除，不再挤占底部空间');
    expect(find.textContaining('已完成'), findsNothing,
        reason: '计划内进度条也已移除，页面上不该再有"已完成 x / y 词"');

    semantics.dispose();
    await tester.pump(const Duration(seconds: 60)); // 放掉节流同步等后台任务
  });

  testWidgets('今日未打卡：主页保持极简不显示印章文案，今日单词数移入高级设置后锁定显示在弹窗内', (tester) async {
    await seedTodayPlan(dakaed: false);
    await pumpTodayPlan(tester);
    await pumpUntil(tester, find.text('新词'));

    expect(find.text('目标已锁定'), findsNothing, reason: '学习已开始后不再展示冗余的"目标已锁定"文字');
    expect(find.byKey(const Key('today_plan_daka_seal_text')), findsNothing,
        reason: '还没打卡就不能盖已打卡的章');
    expect(find.byKey(const Key('today_plan_daka_seal_date')), findsNothing,
        reason: '还没打卡就没有盖章日期');
    expect(find.textContaining('加量已完成'), findsNothing,
        reason: '今天没有加量批次，就不该出现加量进度');

    // 打开右上角高级设置弹窗，校验高级设置菜单正常打开
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.text('高级学习设置'), findsOneWidget);
    expect(find.text('每日计划与词量设置'), findsOneWidget);

    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('加量批次的词数用 +N 跟在新词/旧词数字后面', (tester) async {
    // 必须复现真机档位才守得住：360dp 宽（荣耀 KKG-AN00 逻辑宽）+ 系统字号 1.15 倍。
    // widget 测试默认 800dp 宽，半格富余很多，加量态怎么都不会挤，等于没测。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.reset);
    await seedTodayPlan(dakaed: true, extraWords: 5, extraDone: 2);
    await pumpTodayPlan(tester, textScale: 1.15); // 真机档位
    await pumpUntil(tester, find.text('继续学习（加量）'));

    // 加量词按自己算新词还是旧词并进对应那张卡，两个键只会命中一个
    final extraTags = [
      find.byKey(const Key('today_plan_extra_new_count')),
      find.byKey(const Key('today_plan_extra_old_count')),
    ].where((f) => f.evaluate().isNotEmpty).toList();
    expect(extraTags, hasLength(1), reason: '加量 5 个词要并进新词或旧词的数字里，不会两处都加');
    expect(tester.widget<Text>(extraTags.single).data, ' + 5',
        reason: '加量 5 个词以「 + 5」跟在计划数字后面（一行放全，加号左右各留一个空格）');

    // 左卡一格只有半张卡宽：加量态「5 + 5」叠上左对齐内缩最容易把那一格撑爆
    // （真机曾实测溢出 1.9px），这里必须守住"不溢出"。
    expect(tester.takeException(), isNull, reason: '加量态的数字行不允许溢出');

    // 两格数字必须等大：有加量的那格被挤小时，没加量的那格也要跟着小，
    // 否则同一个左卡里一个大一个小，很难看。
    //
    // 注意这里必须比**渲染出来的矩形**，不能只比 style.fontSize：
    // "各缩各的 FittedBox" 会让同一份 22sp 的 style 渲染出两种大小，
    // 比 style 是抓不到这个 bug 的（试过，没牙）。
    final newRect = tester.getRect(find.byKey(const Key('today_plan_new_count_number')));
    final oldRect = tester.getRect(find.byKey(const Key('today_plan_old_count_number')));
    expect(newRect.height, closeTo(oldRect.height, 0.5),
        reason: '新词与旧词的数字渲染高度必须一致（要小就一样小）');

    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('学完加量批次后广播 TodayStudyListChangedEvent：计划页必须刷新到最新进度，不能停在旧快照',
      (tester) async {
    await seedTodayPlan(dakaed: true, extraWords: 5, extraDone: 2);
    await pumpTodayPlan(tester);
    await pumpUntil(tester, find.text('继续学习（加量）'));
    expect(find.text('继续学习（加量）'), findsOneWidget,
        reason: '进入学习页之前，计划页停在"还有 3 个加量词没学"');

    // 模拟学习页把剩余加量词学完：只改数据，不经过任何页面级刷新
    final extraRows =
        await (db.select(db.learningWords)..where((t) => t.isExtra.equals(true))).get();
    for (final word in extraRows) {
      await db.learningWordsDao
          .saveEntity(word.copyWith(todayLearnedTimes: 99, learnedTimes: 99), false);
    }

    // 学习页跳完成页前广播的业务事实：pushReplacement 会让计划页 push('/bdc') 的
    // future 永不完成，计划页只能靠这个事件刷新，否则会一直显示旧快照
    // （完成页说"加量完成"，计划页却说"还有加量没学"，还会给一个点进去就被弹回的入口）
    EventBus.publishTodayStudyListChanged(const TodayStudyListChangedEvent());
    await pumpUntil(tester, find.text('再来一组（加量）'));

    expect(find.text('再来一组（加量）'), findsOneWidget,
        reason: '收到事件后必须重算加量批次并展示再来一组按钮');
    expect(find.text('继续学习（加量）'), findsNothing,
        reason: '加量已学完，不能再给"继续学习（加量）"入口');

    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('今日已打卡：收起态下在顶部今日xx词右侧直接显示已打卡文字，无需先展开轨道', (tester) async {
    final semantics = tester.ensureSemantics();
    final seal = find.byKey(const Key('today_plan_daka_seal_text'));
    final sealDate = find.byKey(const Key('today_plan_daka_seal_date'));
    final today = AppClock.today();
    final dateLabel = planIslandDateLabel(today);

    await seedTodayPlan(dakaed: true);
    await pumpTodayPlan(tester);
    await pumpUntil(tester, seal);

    expect(seal, findsOneWidget, reason: '学习轨道收起态下，页面顶部今日xx词右侧直接显示已打卡文字');
    expect(tester.getSemantics(seal).label, '已打卡');
    expect(sealDate, findsOneWidget);
    expect(tester.getSemantics(sealDate).label, dateLabel);

    semantics.dispose();
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('编辑态下点击收起轨道：自动退出编辑态，小宠物和主按钮保持显示，卡片不掉底', (tester) async {
    await seedTodayPlan(dakaed: false);
    await pumpTodayPlan(tester);
    await pumpUntil(tester, find.text('学习轨道'));

    // 1. 展开轨道
    await tester.tap(find.text('学习轨道'));
    await tester.pumpAndSettle();

    // 2. 点击「编辑」进入编辑态
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget, reason: '进入编辑态');

    // 3. 不点完成，直接点「收起轨道」
    await tester.tap(find.text('收起轨道'));
    await tester.pumpAndSettle();

    // 4. 断言已自动退出编辑态，小宠物和主操作按钮正常展示
    expect(find.text('完成'), findsNothing, reason: '收起轨道后应自动退出编辑态');
    expect(find.text('继续学习'), findsOneWidget, reason: '底部主操作按钮不能消失');
    expect(find.byType(Image), findsWidgets, reason: '小宠物组件不能消失');

    await tester.pump(const Duration(seconds: 60));
  });
}

