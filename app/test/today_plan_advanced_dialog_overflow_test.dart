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
import 'package:nnbdc/theme/font_scale.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「高级学习设置」对话框在窄屏 + 大档字号下的排版回归。
///
/// 背景：该对话框每行是「左列说明 + 右侧锁定徽章」的 spaceBetween 布局，
/// 左列文本没有任何弹性空间。全局字体放大后（大档 1.15x / 系统无障碍更大），
/// 在 360dp 窄屏上左列会把徽章挤出屏幕（实测溢出 21px）。
///
/// 修复要点：左列改为 Expanded（吃掉剩余宽度）并允许副标题换行。
/// 只加 ellipsis 能消除溢出，却会把提示截成「今日学习已开始，设置暂…」，
/// 用户看不到完整说明——因此这里断言的是"完整可见"，而不只是"不溢出"。
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

  /// 学习已开始 → 对话框进入「锁定」分支（左侧说明 + 右侧锁定徽章同时出现）
  Future<void> seedStartedUser() async {
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

  Future<void> pumpAt(WidgetTester tester, double width, AppFontScale scale) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: DarkMode(),
        child: MaterialApp(
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: AppFontScale.compose(mq.textScaler, scale)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const TodayPlanPage(),
        ),
      ),
    );
    // 页面数据异步就绪：等右上角高级设置入口出现
    for (int i = 0; i < 400 && find.byIcon(Icons.tune_rounded).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  for (final width in [360.0, 390.0]) {
    testWidgets('${width.toInt()}dp 大档下高级学习设置内容完整可见且不溢出', (tester) async {
      await seedStartedUser();
      await pumpAt(tester, width, AppFontScale.large);

      // 页面就绪后清掉首帧期间可能残留的异常，只校验对话框自身的布局
      tester.takeException();

      expect(find.byIcon(Icons.tune_rounded), findsWidgets, reason: '页面应已就绪并出现高级设置入口');
      // 入口是右上角那枚 tune 小圆钮；直接点图标自身的中心，
      // 避免误取到祖先层级里更大范围的 GestureDetector。
      await tester.tapAt(tester.getCenter(find.byIcon(Icons.tune_rounded).first));
      await tester.pumpAndSettle();

      expect(find.text('今日最少新词'), findsOneWidget, reason: '对话框必须真的打开');
      expect(find.text('每组单词数'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '${width.toInt()}dp 大档下对话框文字溢出');

      // 关键：锁定提示必须完整可见，不允许被省略号截成"今日学习已开始，设置暂…"
      const locked = '学习已开始，设置暂时锁定';
      expect(find.text(locked), findsNWidgets(2), reason: '两处设置项都要显示完整锁定提示');
      final over = _overflowingTexts(tester);
      expect(over, isEmpty, reason: '这些文字被截断了(源文本: $over)');
    });
  }
}

/// 收集当前渲染树里所有「布局后发生截断」的文字。
/// 注意：不能查 RenderParagraph.text —— 那只是源文本；省略号是画笔在排版后添加的，
/// 必须查 didExceedMaxLines / didOverflowHeight 这类排版结果。
List<String> _overflowingTexts(WidgetTester tester) {
  final over = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final render = element.renderObject;
    if (render is RenderParagraph && render.didExceedMaxLines) {
      over.add(render.text.toPlainText());
    }
  }
  return over;
}
