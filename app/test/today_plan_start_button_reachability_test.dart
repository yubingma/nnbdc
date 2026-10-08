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

/// 今日计划页的布局回归测试：壁纸底与主题底共用同一套布局。
///
/// 结构事实：外壳 IndexPage 的 Scaffold 开着 extendBody，页面内容铺到屏幕最底部；
/// 而底栏（内容 50 + 底部安全区）虽然透明，但它的 Container 会命中测试整块区域，
/// 于是压在它下面的按钮点不到。所以页面必须把底栏占位（bottomNavReserve）留出来。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  final now = AppClock.now();

  /// 底栏内容高度，与 index.dart 里底栏的 SizedBox(height: navBarContentHeight) 保持一致
  const double navContentHeight = 50;

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

  /// 造一个"今天还没开始学"的账号：今日计划 5 个词一个都没学，主按钮应当是"开始学习"。
  Future<void> seedTodayPlanNotStarted() async {
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
    await db.usersDao.saveUser(user, false);
    Global.currentUserId = userId;
    Global.updateUserCache(user);
    await Prefs.write('currentUserId', userId);

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
    for (int i = 1; i <= 5; i++) {
      await db.into(db.learningWords).insert(LearningWord(
            userId: userId,
            wordId: 'word_$i',
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

  /// 把今日计划页放进与真实外壳同构的 Scaffold（extendBody + 透明底栏）里，
  /// 并模拟目标机型的屏幕尺寸与安全区。[wallpaper] 决定走壁纸底还是主题底。
  Future<void> pumpTodayPlanInShell(
    WidgetTester tester, {
    required Size logicalSize,
    required double topSafeArea,
    required double bottomSafeArea,
    double textScale = 1.0,
    bool wallpaper = true,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = logicalSize;
    tester.view.padding = FakeViewPadding(top: topSafeArea, bottom: bottomSafeArea);
    tester.view.viewPadding = FakeViewPadding(top: topSafeArea, bottom: bottomSafeArea);
    addTearDown(tester.view.reset);

    // 页面在 initState 里读壁纸设置，必须先落盘再 pump
    await Prefs.write(
      'today_plan_wallpaper',
      wallpaper ? 'assets/images/wallpaper/kitty_pink.jpg' : 'none',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: Scaffold(
            extendBody: true,
            backgroundColor: Colors.transparent,
            body: TodayPlanPage(
              bottomNavReserve: navContentHeight + bottomSafeArea,
            ),
            // 与 index.dart 的透明底栏同构：透明 Container 依然占满并吞掉这一整块点击
            bottomNavigationBar: ClipRect(
              child: GestureDetector(
                onLongPress: () {},
                child: Container(
                  decoration: const BoxDecoration(color: Colors.transparent),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: navContentHeight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List<Widget>.generate(
                          3,
                          (i) => Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(Duration.zero);
  }

  Future<void> pumpUntil(WidgetTester tester, Finder finder, {int maxPumps = 400}) async {
    for (int i = 0; i < maxPumps && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 两种背景必须渲染同一套结构：中心目标岛 + 左右双任务卡 + 主按钮。
  void expectSharedStructure() {
    expect(find.text('今日目标'), findsOneWidget, reason: '中心目标岛（壁纸底/主题底共用）');
    expect(find.text('新词'), findsOneWidget, reason: '左侧新词任务卡');
    expect(find.text('旧词'), findsOneWidget, reason: '右侧旧词任务卡');
  }

  Map<String, Rect> layoutGeometry(WidgetTester tester) => <String, Rect>{
        '中心岛': tester.getRect(find.text('今日目标')),
        '新词卡': tester.getRect(find.text('新词')),
        '旧词卡': tester.getRect(find.text('旧词')),
        '主按钮': tester.getRect(find.text('开始学习')),
      };

  /// 断言主按钮既在屏幕里、也在底栏上方，并且真的能被点到。
  Future<void> expectButtonReachable(
    WidgetTester tester,
    Finder button, {
    required double bottomSafeArea,
  }) async {
    expect(button, findsOneWidget, reason: '主按钮必须存在');

    // 内容比屏幕高时（小屏/横屏/大字号）用户能滚动到底，按钮必须仍然可点
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable.first, const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.drag(scrollable.first, const Offset(0, -800));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull, reason: '任何分辨率下都不允许溢出报错');

    // 量的是按钮真正的点击区（InkWell 的带内边距盒子），不是文字本身
    final tapBox = find.ancestor(of: button, matching: find.byType(InkWell)).first;
    final Rect rect = tester.getRect(tapBox);
    final double screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final double navTop = screenHeight - (navContentHeight + bottomSafeArea);
    expect(rect.top, greaterThanOrEqualTo(0.0), reason: '按钮不能被顶出屏幕顶部');
    expect(rect.bottom, lessThanOrEqualTo(navTop + 0.5),
        reason: '按钮必须完整落在底栏上方，否则会被透明底栏吞掉点击');
    expect(rect.height, greaterThanOrEqualTo(48.0),
        reason: '主按钮命中区要够高（≈52），不能是个小细条');
    expect(navTop - rect.bottom, greaterThanOrEqualTo(12.0),
        reason: '按钮下沿到底栏命中区至少留 12（最初那版的值），再低就贴到误触区了');

    final hit = tester.hitTestOnBinding(tester.getCenter(button));
    expect(hit.path.map((e) => e.target), contains(tester.renderObject(button)),
        reason: '按钮中心必须真的命中按钮本身（不能被底栏挡住）');
  }

  for (final wallpaper in <bool>[true, false]) {
    final bg = wallpaper ? '壁纸底' : '主题底';

    testWidgets('$bg · iPhone 15 尺寸：开始学习按钮完整落在透明底栏上方且可点', (tester) async {
      await seedTodayPlanNotStarted();
      await pumpTodayPlanInShell(tester,
          logicalSize: const Size(393, 852),
          topSafeArea: 59,
          bottomSafeArea: 34,
          wallpaper: wallpaper);
      await pumpUntil(tester, find.text('开始学习'));

      expectSharedStructure();
      await expectButtonReachable(tester, find.text('开始学习'), bottomSafeArea: 34);

      await tester.pump(const Duration(seconds: 60));
    });

    testWidgets('$bg · iPhone SE 尺寸（无底部安全区）：开始学习按钮同样可点', (tester) async {
      await seedTodayPlanNotStarted();
      await pumpTodayPlanInShell(tester,
          logicalSize: const Size(320, 568),
          topSafeArea: 20,
          bottomSafeArea: 0,
          wallpaper: wallpaper);
      await pumpUntil(tester, find.text('开始学习'));

      expectSharedStructure();
      await expectButtonReachable(tester, find.text('开始学习'), bottomSafeArea: 0);

      await tester.pump(const Duration(seconds: 60));
    });

    testWidgets('$bg · 小屏横屏：内容放不下时能滚到底，开始学习按钮依然可点', (tester) async {
      await seedTodayPlanNotStarted();
      await pumpTodayPlanInShell(tester,
          logicalSize: const Size(667, 375),
          topSafeArea: 0,
          bottomSafeArea: 21,
          wallpaper: wallpaper);
      await pumpUntil(tester, find.text('开始学习'));

      expectSharedStructure();
      await expectButtonReachable(tester, find.text('开始学习'), bottomSafeArea: 21);

      await tester.pump(const Duration(seconds: 60));
    });

    testWidgets('$bg · 小屏 + 大字号：内容放不下时能滚到底，开始学习按钮依然可点', (tester) async {
      await seedTodayPlanNotStarted();
      await pumpTodayPlanInShell(tester,
          logicalSize: const Size(320, 568),
          topSafeArea: 20,
          bottomSafeArea: 0,
          textScale: 2.0,
          wallpaper: wallpaper);
      await pumpUntil(tester, find.text('开始学习'));

      expectSharedStructure();
      await expectButtonReachable(tester, find.text('开始学习'), bottomSafeArea: 0);

      await tester.pump(const Duration(seconds: 60));
    });
  }

  testWidgets('壁纸底与主题底：同一套布局，几何逐项完全一致', (tester) async {
    await seedTodayPlanNotStarted();
    await pumpTodayPlanInShell(tester,
        logicalSize: const Size(393, 852), topSafeArea: 59, bottomSafeArea: 34, wallpaper: true);
    await pumpUntil(tester, find.text('开始学习'));
    final wallpaperGeometry = layoutGeometry(tester);

    // 彻底卸载页面再重建，让它重新读取壁纸设置切到主题底
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpTodayPlanInShell(tester,
        logicalSize: const Size(393, 852), topSafeArea: 59, bottomSafeArea: 34, wallpaper: false);
    await pumpUntil(tester, find.text('开始学习'));
    final themeGeometry = layoutGeometry(tester);

    expect(themeGeometry, equals(wallpaperGeometry),
        reason: '两种背景必须共用同一套布局，只有卡片皮肤不同');

    await tester.pump(const Duration(seconds: 60));
  });
}
