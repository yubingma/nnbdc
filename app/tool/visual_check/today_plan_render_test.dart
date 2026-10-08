import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/today_plan.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 今日计划页「人眼过一遍」的渲染脚手架（手动跑，不进默认测试套件）。
///
/// 用真实壁纸 + 真实字体把页面渲染成 PNG，用来核对断言语料看不出来的观感：
/// 卡片字色在真实照片上是否看得清、按钮与底栏的距离、两种背景是否同构。
///
/// 跑法：flutter test tool/visual_check/today_plan_render_test.dart
/// 出图：/Volumes/ssd/ppdc/tmp/today_plan_shots/*.png
///
/// 注意：字体路径取自本机 macOS 与 Flutter SDK 缓存，换机器需要改 [materialFonts] 与中文字体路径。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  final now = AppClock.now();
  const outDir = '/Volumes/ssd/ppdc/tmp/today_plan_shots';
  final rootKey = GlobalKey();
  const navContentHeight = 50.0;

  setUpAll(() async {
    // 测试默认字体是方块字，必须装载真实字体才能看出观感：中文 / 数字(Roboto) / 图标(MaterialIcons)
    Future<void> loadFont(String family, List<String> paths) async {
      final loader = FontLoader(family);
      for (final path in paths) {
        final bytes = File(path).readAsBytesSync();
        loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
      }
      await loader.load();
    }

    const materialFonts = '/Users/myb/dev/flutter/bin/cache/artifacts/material_fonts';
    await loadFont('AppCJK', ['/System/Library/Fonts/Supplemental/Arial Unicode.ttf']);
    // 页面里数字显式指定了 fontFamily: 'Roboto'，其中还混着汉字；测试环境没有系统兜底字体，
    // 直接把中文字体注册成 Roboto 家族，混排才不会掉进方块（真机上由系统字体兜底，无需处理）
    await loadFont('Roboto', ['/System/Library/Fonts/Supplemental/Arial Unicode.ttf']);
    await loadFont('MaterialIcons', ['$materialFonts/MaterialIcons-Regular.otf']);

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
    Directory(outDir).createSync(recursive: true);
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    StudyCacheManager().clear();
    // ignore: invalid_use_of_visible_for_testing_member —— 本文件在 test/ 之外，但同样是测试进程
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Global.commonDictId = 'mock_dict_1';
  });

  tearDown(() async {
    await db.close();
    Global.currentUserId = null;
    Global.commonDictId = '0';
  });

  Future<void> seed({required bool dakaed, int extraWords = 0, int extraDone = 0, int wordsPerDay = 12}) async {
    const String userId = 'test_user_id';
    final user = User(
      id: userId,
      userName: 'mock_user',
      password: '',
      nickName: 'Tester',
      email: '',
      gameScore: 0,
      dakaScore: 0,
      learnedDays: 3,
      learningFinished: false,
      inviteAwardTaken: false,
      isSuperAdmin: false,
      isAdmin: false,
      isInputor: false,
      cowDung: 0,
      throwDiceChance: 0,
      wordsPerDay: wordsPerDay,
      dakaDayCount: 2,
      masteredWordsCount: 0,
      maxContinuousDakaDayCount: 2,
      continuousDakaDayCount: 2,
      todayStudyStarted: dakaed,
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
          wordCount: 20,
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
    Future<void> addWord(String wordId, int batchId, bool isExtra, int learned) async {
      await db.into(db.learningWords).insert(LearningWord(
            userId: userId,
            wordId: wordId,
            addTime: now,
            addDay: 1,
            batchId: batchId,
            stability: 0.0,
            isTodayNewWord: true,
            learnedTimes: learned,
            todayLearnedTimes: learned,
            lastLearningDate: now,
            learningOrder: 0,
            createTime: now,
            updateTime: now,
            isExtra: isExtra,
          ));
    }

    for (int i = 1; i <= 12; i++) {
      await addWord('word_$i', 1, false, dakaed ? 99 : 0);
    }
    for (int i = 1; i <= extraWords; i++) {
      await addWord('word_${12 + i}', 2, true, i <= extraDone ? 99 : 0);
    }
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required String wallpaper,
    required bool darkTheme,
    required bool dakaed,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    await Prefs.write('today_plan_wallpaper', wallpaper);

    final darkMode = DarkMode();
    darkMode.setThemeStyle(darkTheme ? AppThemeStyle.midnight : AppThemeStyle.emerald);

    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: ChangeNotifierProvider<DarkMode>.value(
        value: darkMode,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          // 汉字走刚装载的真实字体，避免出图全是方块
          theme: ThemeData(fontFamily: 'AppCJK', useMaterial3: false),
          home: Scaffold(
            extendBody: true,
            backgroundColor: Colors.transparent,
            body: TodayPlanPage(bottomNavReserve: navContentHeight + 34),
            // 与 index.dart 同构的透明底栏（只看观感，图标随便放三个）
            bottomNavigationBar: ClipRect(
              child: Container(
                decoration: const BoxDecoration(color: Colors.transparent),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: navContentHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: const [
                        Icon(Icons.menu_book_rounded, color: Color(0xFF2CD88F), size: 24),
                        Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 22),
                        Icon(Icons.person_rounded, color: Color(0xFF64748B), size: 22),
                      ],
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
    // 壁纸解码是真实引擎异步，必须让真实事件循环跑起来，否则照片永远出不来
    if (wallpaper != 'none') {
      await tester.runAsync(() async {
        await precacheImage(AssetImage(wallpaper), tester.element(find.byType(MaterialApp)));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
    }
    await tester.pump();
    for (int i = 0; i < 600; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final state = tester.state<TodayPlanPageState>(find.byType(TodayPlanPage));
      if (state.dataLoaded && find.textContaining('学习').evaluate().isNotEmpty) break;
    }
    final finalState = tester.state<TodayPlanPageState>(find.byType(TodayPlanPage));
    debugPrint('RENDER dataLoaded=${finalState.dataLoaded} '
        'island=${find.text('今日目标').evaluate().length} '
        'seal=${find.text('已打卡').evaluate().length} '
        'start=${find.text('开始学习').evaluate().length} '
        'cont=${find.text('继续学习').evaluate().length}');
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final boundary = rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  }

  Future<void> renderCase(
    WidgetTester tester, {
    required String name,
    required String wallpaper,
    required bool darkTheme,
    bool dakaed = false,
    int extraWords = 0,
    int extraDone = 0,
    int wordsPerDay = 12,
  }) async {
    await seed(
        dakaed: dakaed, extraWords: extraWords, extraDone: extraDone, wordsPerDay: wordsPerDay);
    await pumpPage(tester, wallpaper: wallpaper, darkTheme: darkTheme, dakaed: dakaed);
    await tester.runAsync(() => shoot(tester, name));
    await tester.pump(const Duration(seconds: 60));
  }

  testWidgets('渲染 石韵 · 浅色主题（用户报的问题图）', (tester) async {
    await renderCase(tester,
        name: '01_shiyun_light', wallpaper: 'assets/images/wallpaper/stone.jpg', darkTheme: false);
  });

  testWidgets('渲染 石韵 · 深色主题', (tester) async {
    await renderCase(tester,
        name: '02_shiyun_dark', wallpaper: 'assets/images/wallpaper/stone.jpg', darkTheme: true);
  });

  testWidgets('渲染 石韵 · 已打卡（印章 + 继续学习按钮）', (tester) async {
    await renderCase(tester,
        name: '03_shiyun_daka',
        wallpaper: 'assets/images/wallpaper/stone.jpg',
        darkTheme: false,
        dakaed: true,
        extraWords: 5,
        extraDone: 2);
  });

  testWidgets('渲染 竹韵 · 浅色主题', (tester) async {
    await renderCase(tester,
        name: '04_zhuyun_light', wallpaper: 'assets/images/wallpaper/bamboo.jpg', darkTheme: false);
  });

  testWidgets('渲染 经典（主题底）· 浅色主题', (tester) async {
    await renderCase(tester, name: '07_classic_light', wallpaper: 'none', darkTheme: false);
  });

  testWidgets('渲染 水趣（蓝猫）· 浅色主题', (tester) async {
    await renderCase(tester,
        name: '10_kitty_blue_light',
        wallpaper: 'assets/images/wallpaper/kitty_blue.jpg',
        darkTheme: false);
  });

  testWidgets('渲染 水趣（蓝猫）· 深色主题', (tester) async {
    await renderCase(tester,
        name: '11_kitty_blue_dark',
        wallpaper: 'assets/images/wallpaper/kitty_blue.jpg',
        darkTheme: true);
  });

  testWidgets('渲染 粉梦（粉猫）· 浅色主题', (tester) async {
    await renderCase(tester,
        name: '12_kitty_pink_light',
        wallpaper: 'assets/images/wallpaper/kitty_pink.jpg',
        darkTheme: false);
  });

  testWidgets('渲染 粉梦（粉猫）· 深色主题', (tester) async {
    await renderCase(tester,
        name: '13_kitty_pink_dark',
        wallpaper: 'assets/images/wallpaper/kitty_pink.jpg',
        darkTheme: true);
  });

  testWidgets('渲染 绿荫（大树草地）· 浅色主题', (tester) async {
    await renderCase(tester,
        name: '14_tree_green_light',
        wallpaper: 'assets/images/wallpaper/tree_green.jpg',
        darkTheme: false);
  });

  testWidgets('渲染 绿荫（大树草地）· 深色主题', (tester) async {
    await renderCase(tester,
        name: '15_tree_green_dark',
        wallpaper: 'assets/images/wallpaper/tree_green.jpg',
        darkTheme: true);
  });
}
