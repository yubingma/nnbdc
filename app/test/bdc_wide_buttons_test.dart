import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/bdc/bdc.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/page/word_detail.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/fsrs.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart' as provider;

class MockBdcNotifierForWideScreen extends BdcNotifier {
  final BdcState initialState;
  bool mockHasSeenAnswer;

  MockBdcNotifierForWideScreen(this.initialState, {this.mockHasSeenAnswer = false});

  @override
  BdcState build() {
    return initialState;
  }

  @override
  bool get hasSeenAnswer => mockHasSeenAnswer;

  void updateMockState(BdcState newState, {bool? hasSeen}) {
    if (hasSeen != null) mockHasSeenAnswer = hasSeen;
    state = newState;
  }

  @override
  Future<void> loadData(BuildContext? context, {bool isAutoTest = false}) async {}
}

(WordVo, GetWordResult) _createTestData() {
  final testWord = WordVo.c2('apple')
    ..id = 'w_apple'
    ..setMeaningStr('n. 苹果');

  testWord.meaningItems = [
    MeaningItemVo('mi_1', 'n.', '苹果', null, null, []),
  ];

  final testLw = LearningWordVo(
    UserVo.c2('user1'),
    DateTime.now(),
    1,
    DateTime.now(),
    1,
    0,
    testWord,
  );

  final mockGetWordResult = GetWordResult(
    testLw,
    0,
    null,
    [1, 10],
    null,
    false,
    false,
    [],
    [],
    [],
    null,
    [],
    [],
    [],
    false,
    false,
  );

  return (testWord, mockGetWordResult);
}

Widget _buildPageWithNotifier(MockBdcNotifierForWideScreen notifier) {
  return provider.ChangeNotifierProvider<DarkMode>(
    create: (_) => DarkMode(),
    child: ProviderScope(
      overrides: [
        bdcNotifierProvider.overrideWith(() => notifier),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: BdcPage(),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    PlatformUtils.asrSupportedOverride = true;
    PlatformUtils.englishAsrSupportedOverride = true;
    PlatformUtils.isDesktopOverride = false;
  });

  tearDown(() {
    PlatformUtils.asrSupportedOverride = null;
    PlatformUtils.englishAsrSupportedOverride = null;
    PlatformUtils.isDesktopOverride = null;
  });

  testWidgets('iPad 宽屏设备下学习页面按钮布局与对称性测试', (tester) async {
    // 模拟 iPad 宽屏（宽度 >= 560，如 800x1000）
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final (testWord, mockResult) = _createTestData();
    final wordWrapper = WordWrapper(testWord, null);

    // 阶段 1：下一词未出现（hasSeenAnswer: false）
    final stateStage1 = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockResult,
      wordWrapper: wordWrapper,
      studyStep: StudyStep.en2Ch.json,
      showAnswerButtons: true,
      canLeaveCurrWord: false,
    );

    final notifier = MockBdcNotifierForWideScreen(stateStage1, mockHasSeenAnswer: false);

    await tester.pumpWidget(_buildPageWithNotifier(notifier));
    await tester.pumpAndSettle();

    final notKnowFinder = find.byKey(const Key('bdc_not_know_btn'));
    final studyAgainFinder = find.byKey(const Key('bdc_study_again'));
    final nextWordFinder = find.byKey(const Key('bdc_next_word_btn'));

    expect(notKnowFinder, findsOneWidget, reason: '应展示「不认识」按钮');
    expect(studyAgainFinder, findsOneWidget, reason: '应展示「再学学」按钮');
    expect(nextWordFinder, findsNothing, reason: '未看答案前不得展示真实的「下一词」流转按钮');

    // 获取坐标与尺寸
    final notKnowRect = tester.getRect(notKnowFinder);
    final studyAgainRect = tester.getRect(studyAgainFinder);

    final leftSpace = notKnowRect.left; // 不认识左侧到屏幕左边缘的空间
    final rightSpace = 800.0 - studyAgainRect.right; // 再学学右侧到屏幕右边缘的空间

    // 验证对称性：不认识左侧的空间和再学学右侧的空间必须严格相等（误差允许在 1px 像素取整以内）
    expect((leftSpace - rightSpace).abs(), lessThan(1.0),
        reason: '未出现下一词时，不认识左侧空间($leftSpace)必须与再学学右侧空间($rightSpace)严格相等以保持左右对称');

    final stage1StudyAgainPos = tester.getTopLeft(studyAgainFinder);
    final stage1NotKnowPos = tester.getTopLeft(notKnowFinder);

    // 阶段 2：答案揭晓，下一词按钮出现（hasSeenAnswer: true, canLeaveCurrWord: true）
    final stateStage2 = stateStage1.copyWith(
      canLeaveCurrWord: true,
    );

    notifier.updateMockState(stateStage2, hasSeen: true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bdc_next_word_btn')), findsOneWidget,
        reason: '此时应展示「下一词」流转按钮');

    final stage2StudyAgainPos = tester.getTopLeft(studyAgainFinder);
    final stage2NotKnowPos = tester.getTopLeft(notKnowFinder);
    final nextWordRect = tester.getRect(find.byKey(const Key('bdc_next_word_btn')));

    // 核心细节验证 1：下一词按钮出现时，再学学按钮的位置不要移动（0 偏移）
    expect((stage2StudyAgainPos.dx - stage1StudyAgainPos.dx).abs(), lessThan(0.1),
        reason: '当下一词按钮出现时，再学学按钮的水平位置绝对不要移动');
    expect((stage2StudyAgainPos.dy - stage1StudyAgainPos.dy).abs(), lessThan(0.1),
        reason: '当下一词按钮出现时，再学学按钮的垂直位置绝对不要移动');

    // 核心细节验证 2：不认识按钮的位置同样保持不动
    expect((stage2NotKnowPos.dx - stage1NotKnowPos.dx).abs(), lessThan(0.1),
        reason: '当下一词按钮出现时，不认识按钮的位置保持不动');

    // 核心细节验证 3：下一词出现在再学学右侧预留的位置
    expect(nextWordRect.left, greaterThan(studyAgainRect.right),
        reason: '下一词必须出现在再学学右方');

    // 核心细节验证 4：此时打破对称性（最右侧是下一词，离右边缘更近）
    final newRightSpace = 800.0 - nextWordRect.right;
    expect(newRightSpace, lessThan(leftSpace),
        reason: '只有当下一词按钮出现时，才允许打破左右对称');

    // 核心细节验证 5：在 800px 宽屏下，主学习页下一词右边距必须为严格的 28.0px
    final bdcRightMargin = 800.0 - nextWordRect.right;
    expect(bdcRightMargin, 28.0, reason: '学习主页下一词右边距为 28.0px (16px 外边距 + 12px 间距)');
  });

  testWidgets('手机窄屏设备下按钮保持居中排列', (tester) async {
    // 模拟 iPhone 窄屏（例如 390x844）
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final (testWord, mockResult) = _createTestData();
    final wordWrapper = WordWrapper(testWord, null);

    final state = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockResult,
      wordWrapper: wordWrapper,
      studyStep: StudyStep.en2Ch.json,
      showAnswerButtons: true,
      canLeaveCurrWord: true,
    );

    final notifier = MockBdcNotifierForWideScreen(state, mockHasSeenAnswer: true);

    await tester.pumpWidget(_buildPageWithNotifier(notifier));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bdc_not_know_btn')), findsOneWidget);
    expect(find.byKey(const Key('bdc_study_again')), findsOneWidget);
    expect(find.byKey(const Key('bdc_next_word_btn')), findsOneWidget);

    // 手机窄屏下三个按钮紧密排列并居中
    final notKnowRect = tester.getRect(find.byKey(const Key('bdc_not_know_btn')));
    final nextWordRect = tester.getRect(find.byKey(const Key('bdc_next_word_btn')));

    // 左右留白相近（整体居中）
    final leftPadding = notKnowRect.left;
    final rightPadding = 390.0 - nextWordRect.right;
    expect((leftPadding - rightPadding).abs(), lessThan(10.0),
        reason: '手机窄屏下三个按钮整体应居中排列');
  });

  testWidgets('单词详情页下一词按钮在宽屏设备上右边距同样为28px（与主学习页完全相同位置，心智负担最低）', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final (testWord, _) = _createTestData();

    final detailArgs = WordDetailPageArgs(
      testWord,
      false,
      null,
      false,
      showNextWordButton: true,
      autoPlayWordOnEnter: false,
    );

    final router = GoRouter(
      initialLocation: '/word_detail',
      initialExtra: detailArgs,
      routes: [
        GoRoute(
          path: '/word_detail',
          builder: (context, routerState) => const WordDetailPage(),
        ),
      ],
    );

    await tester.pumpWidget(
      provider.ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final detailNextWordFinder = find.byKey(const Key('detail_next_word_btn'));
    expect(detailNextWordFinder, findsOneWidget, reason: '详情页应展示带有 detail_next_word_btn Key 的下一词按钮');
    final detailNextWordRect = tester.getRect(detailNextWordFinder);
    final detailRightMargin = 800.0 - detailNextWordRect.right;

    // 验证详情页下一词右边距为 28.0px，与主学习页完全一致
    expect((detailRightMargin - 28.0).abs(), lessThan(1.0),
        reason: '详情页下一词按钮右边距($detailRightMargin)必须与主页面下一词按钮右边距(28.0)完全相同以降低心智负担');
  });

  testWidgets('本环节重练不计分：评分面板只呈现已记入的真实成绩，不呈现本次推算的下次复习天数', (tester) async {
    final (testWord, mockResult) = _createTestData();
    final wordWrapper = WordWrapper(testWord, null);

    final state = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockResult,
      wordWrapper: wordWrapper,
      studyStep: StudyStep.en2Ch.json,
      showAnswerButtons: true,
      canLeaveCurrWord: true,
      hasFinishedAnswering: true,
      // 本次是本环节重练：评分不写日志、记忆状态不更新（study_bo 的 isGraded=false）
      isGroupStepRetry: true,
      lastFsrsRating: FsrsRating.easy,
      // 本次推算出的"下次复习 12 天"是假的：它不会被记入
      fsrsItem: FSRSItem(
        stability: 20,
        difficulty: 5,
        elapsedDays: 0,
        scheduledDays: 12,
        reps: 2,
        lapses: 0,
        state: FsrsState.review,
      ),
      todayLatestRating: FsrsRating.again,
    );

    final notifier = MockBdcNotifierForWideScreen(state, mockHasSeenAnswer: true);
    // 该词今天真实的评分流水：测评那一条（忘记，1 天后），重练不会新增流水
    notifier.learningHistoryFuture = Future.value([
      LearningLog(
        id: 'log_1',
        userId: 'user1',
        wordId: 'w_apple',
        rating: FsrsRating.again.value,
        stability: 1.0,
        difficulty: 5.0,
        elapsedDays: 0,
        scheduledDays: 1,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ),
    ]);

    await tester.pumpWidget(_buildPageWithNotifier(notifier));
    await tester.pumpAndSettle();

    expect(find.textContaining('测评结果: 忘记'), findsOneWidget,
        reason: '重练不计分：面板必须呈现今天真实记入的测评结果，而不是本次重练的评分');
    expect(find.textContaining('测评结果: 轻松'), findsNothing,
        reason: '不得把本次重练的评分当成测评成绩展示');
    expect(find.textContaining('下次复习: 1天后', findRichText: true), findsOneWidget,
        reason: '下次复习天数必须来自已记入的流水');
    expect(find.textContaining('下次复习: 12天后', findRichText: true), findsNothing,
        reason: '不得展示本次重练推算出的、不会生效的下次复习天数');
  });

  testWidgets('回看模式横幅必须参与布局，不得遮挡顶部「返回/掌握/报错」按钮', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    // 真机状态栏高度：横幅此前用 Positioned 悬浮在页面顶部，
    // 其"状态栏 + 文字"的总高度会盖住紧贴状态栏下方的顶部按钮行
    tester.view.padding = const FakeViewPadding(top: 47);
    // 大字号（App 字号设置/系统字号）会直接把悬浮横幅的文字撑高，盖子随之加深
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    final (testWord, mockResult) = _createTestData();
    final wordWrapper = WordWrapper(testWord, null);
    final state = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockResult,
      wordWrapper: wordWrapper,
      studyStep: StudyStep.en2Ch.json,
      showAnswerButtons: true,
      canLeaveCurrWord: true,
      history: [mockResult],
      historyIndex: 0,
    );
    final notifier = MockBdcNotifierForWideScreen(state, mockHasSeenAnswer: true);

    await tester.pumpWidget(_buildPageWithNotifier(notifier));
    await tester.pumpAndSettle();

    final bannerFinder = find.text('回看模式');
    expect(bannerFinder, findsOneWidget, reason: '回看模式应展示横幅');

    // 量的是橙色横条本体（Container），不是其中的文字
    final bannerRect = tester.getRect(find.byKey(const Key('review_mode_banner')));
    final masteredIconRect =
        tester.getRect(find.byIcon(Icons.check_circle_outline_rounded));
    final backLabelRect = tester.getRect(find.text('返回'));
    debugPrint('回看横幅条=$bannerRect 掌握图标=$masteredIconRect 返回文字=$backLabelRect');

    // 横幅不遮挡「掌握」图标（顶部按钮行中最高的一员）
    expect(bannerRect.bottom, lessThanOrEqualTo(masteredIconRect.top),
        reason: '回看横幅底边必须落在顶部按钮行之上，否则会盖住「掌握」按钮');
    expect(bannerRect.bottom, lessThanOrEqualTo(backLabelRect.top),
        reason: '回看横幅底边必须落在顶部按钮行之上，否则会盖住「返回」按钮');
  });
}
