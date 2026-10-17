import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/today_plan.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme_background.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  final now = AppClock.now();

  // 只匹配壁纸照片（assets/images/wallpaper/*）的那张 Image。
  // 页面里还有宠物陪伴等其它插图，用 find.byType(Image) 会把它们一并算进来，断言就失真了。
  final wallpaperImageFinder = find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName.startsWith('assets/images/wallpaper/'),
    description: '壁纸照片 Image',
  );

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
          name: '四级词汇',
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

  Future<void> pumpPage(WidgetTester tester, {required double width, required double height}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
  }

  testWidgets('宽屏形态下：隐藏手机壁纸，仅允许经典背景，并渲染经典自适应背景', (tester) async {
    await seedUser();
    // 模拟之前在手机端保存了某张手机壁纸
    await Prefs.write('today_plan_wallpaper', 'assets/images/wallpaper/amber.jpg');

    // 宽屏尺寸（例如 iPad 竖屏 768x1024，宽高比 0.75 >= 0.62，宽度 >= 600）
    await pumpPage(tester, width: 768, height: 1024);
    tester.takeException();

    // 1. 验证背景：即使 Prefs 里存的是 amber.jpg，宽屏下有效壁纸仍强制为 none，渲染 AppThemeBackground
    expect(find.byType(AppThemeBackground), findsOneWidget);
    // 只看壁纸照片这一张（页面里还有宠物陪伴等其它插图，不该被算进壁纸断言）
    expect(wallpaperImageFinder, findsNothing);

    // 2. 打开高级学习设置弹窗
    expect(find.byIcon(Icons.tune_rounded), findsWidgets);
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.tune_rounded).first));
    await tester.pumpAndSettle();

    // 3. 验证弹窗中只展示经典壁纸，隐藏其它手机壁纸
    expect(find.text('经典'), findsOneWidget);
    expect(find.text('壁纸仅适配手机竖屏，宽屏暂仅支持经典背景'), findsOneWidget);
    expect(find.text('星砂'), findsNothing);
    expect(find.text('琥珀'), findsNothing);
    expect(find.text('水趣'), findsNothing);
    expect(find.text('随机'), findsNothing);

    // 4. 点击「经典」药丸
    await tester.tap(find.text('经典'));
    await tester.pumpAndSettle();

    // 验证写入的壁纸为 none
    expect(Prefs.read<String>('today_plan_wallpaper'), 'none');
  });

  testWidgets('手机窄屏形态下：展示全部 20 个壁纸选项，且选定壁纸正常生效', (tester) async {
    await seedUser();
    await Prefs.write('today_plan_wallpaper', 'assets/images/wallpaper/amber.jpg');

    // 手机窄屏尺寸（390x844，宽高比 0.46 < 0.62）
    await pumpPage(tester, width: 390, height: 844);
    tester.takeException();

    // 1. 验证背景：手机窄屏下壁纸生效，渲染壁纸照片
    expect(wallpaperImageFinder, findsOneWidget);

    // 2. 打开高级学习设置弹窗
    expect(find.byIcon(Icons.tune_rounded), findsWidgets);
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.tune_rounded).first));
    await tester.pumpAndSettle();

    // 3. 验证弹窗中 20 个壁纸全部可选
    expect(find.text('经典'), findsOneWidget);
    expect(find.text('随机'), findsOneWidget);
    expect(find.text('星砂'), findsOneWidget);
    expect(find.text('琥珀'), findsOneWidget);
    expect(find.text('水趣'), findsOneWidget);
    expect(find.text('壁纸仅适配手机竖屏，宽屏暂仅支持经典背景'), findsNothing);
  });
}
