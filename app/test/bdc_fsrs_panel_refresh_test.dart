import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/bdc/bdc.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/fsrs.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart' as provider;

/// 评分面板（测评结果 + 下次复习天数）的刷新口径测试。
///
/// 面板显示的数据（lastFsrsRating / fsrsItem / todayLatestRating）刻意不进
/// [BdcStateUiSignature]（改判时不让学习页整页重建、与详情页转场首帧抢帧），
/// 因此面板必须自己订阅这些字段（见 BdcPageState 的 `_buildLiveFsrsResultPanel`）。
/// 这里锁死"改判后立刻所见即所得"：界面上的评分与下次复习天数必须等于最后表态。
class MockBdcNotifierForPanel extends BdcNotifier {
  final BdcState initialState;
  bool mockHasSeenAnswer;
  bool mockHasUnsubmittedAnswer;

  MockBdcNotifierForPanel(this.initialState,
      {this.mockHasSeenAnswer = false, this.mockHasUnsubmittedAnswer = false});

  @override
  BdcState build() => initialState;

  @override
  bool get hasSeenAnswer => mockHasSeenAnswer;

  /// 本次作答"已受理、尚未落库"（面板那一行显示的就是它）。
  @override
  bool get hasUnsubmittedAnswer => mockHasUnsubmittedAnswer;

  /// 模拟 BdcNotifier.showWordDetail(fsrsRating: ...) 改写评分；
  /// 真实链路里被改写的就是这几个字段（见 bdc_notifier.dart 的 showWordDetail）。
  void applyReGrade(FsrsRating rating, {required FSRSItem fsrsItem, String? reason}) {
    state = state.copyWith(
      lastFsrsRating: rating,
      lastFsrsRatingReason: reason,
      isScorePassed: rating != FsrsRating.again,
      fsrsItem: fsrsItem,
    );
  }

  /// 捕获「再学学」等入口经 showWordDetail 传下来的评分与对错标记（不真正跳详情页）。
  FsrsRating? capturedDetailRating;
  bool? capturedDetailIsWrong;

  @override
  Future<void> showWordDetail(WordVo word, bool isAnswerWrong, BuildContext? context,
      {FsrsRating? fsrsRating, String? reason, bool autoPlayWordOnEnter = true}) async {
    capturedDetailRating = fsrsRating;
    capturedDetailIsWrong = isAnswerWrong;
  }

  @override
  Future<void> loadData(BuildContext? context, {bool isAutoTest = false}) async {}
}

(WordVo, GetWordResult) _createTestData({int stepIndex = 0}) {
  final testWord = WordVo.c2('apple')
    ..id = 'w_apple'
    ..setMeaningStr('n. 苹果');
  testWord.meaningItems = [MeaningItemVo('mi_1', 'n.', '苹果', null, null, [])];

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
    testLw, stepIndex, null, [1, 10], null, false, false, [], [], [], null, [], [], [], false, false,
  );

  return (testWord, mockGetWordResult);
}

Widget _buildPageWithNotifier(MockBdcNotifierForPanel notifier) {
  return provider.ChangeNotifierProvider<DarkMode>(
    create: (_) => DarkMode(),
    child: ProviderScope(
      overrides: [bdcNotifierProvider.overrideWith(() => notifier)],
      child: const MaterialApp(home: Scaffold(body: BdcPage())),
    ),
  );
}

/// 测评环节答对"良好"这一刻的页面状态（页面此时已按签名重建，面板显示良好）。
BdcState _answeredGoodState(WordVo word, GetWordResult result, FSRSItem fsrsItem) {
  return const BdcState().copyWith(
    dataLoaded: true,
    word: word,
    currentGetWordResult: result,
    wordWrapper: WordWrapper(word, null),
    studyStep: StudyStep.en2Ch.json,
    showAnswerButtons: true,
    canLeaveCurrWord: true,
    hasFinishedAnswering: true,
    isScorePassed: true,
    lastFsrsRating: FsrsRating.good,
    fsrsItem: fsrsItem,
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

  Future<void> pumpPage(WidgetTester tester, MockBdcNotifierForPanel notifier) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(_buildPageWithNotifier(notifier));
    await tester.pumpAndSettle();
  }

  testWidgets('测评答对(良好)后改判「不认识」：面板必须立刻改为忘记，不得停在良好', (tester) async {
    final (testWord, mockResult) = _createTestData();
    final fsrs = FSRS();
    final notifier = MockBdcNotifierForPanel(
      _answeredGoodState(testWord, mockResult, fsrs.init(FsrsRating.good)),
      mockHasSeenAnswer: true,
    );
    await pumpPage(tester, notifier);

    expect(find.text('当前评分: 良好'), findsOneWidget, reason: '答对后面板显示当前评分');

    // 用户改点「不认识」：评分被改判为忘记（不点「下一词」，直接进详情页再返回）
    final againItem = fsrs.init(FsrsRating.again);
    notifier.applyReGrade(FsrsRating.again,
        fsrsItem: againItem, reason: '主动点击了不再认识，评分: 忘记');
    await tester.pumpAndSettle();

    expect(find.text('当前评分: 良好'), findsNothing,
        reason: '最后表态是「不认识」＝忘记，界面不得继续显示良好（所见即所得）');
    expect(find.text('当前评分: 忘记'), findsOneWidget);
    expect(find.textContaining('下次复习: ${againItem.scheduledDays}天后', findRichText: true),
        findsOneWidget,
        reason: '评分改了，面板上的下次复习天数必须按新评分重算');
  });

  testWidgets('改判为良好（修改今日评分等入口）：面板必须跟着刷新', (tester) async {
    final (testWord, mockResult) = _createTestData();
    final fsrs = FSRS();
    final easyItem = fsrs.init(FsrsRating.easy);
    final state = _answeredGoodState(testWord, mockResult, easyItem)
        .copyWith(lastFsrsRating: FsrsRating.easy);
    final notifier = MockBdcNotifierForPanel(state, mockHasSeenAnswer: true);
    await pumpPage(tester, notifier);

    expect(find.text('当前评分: 轻松'), findsOneWidget);

    final goodItem = fsrs.init(FsrsRating.good);
    notifier.applyReGrade(FsrsRating.good,
        fsrsItem: goodItem, reason: '手动修正本次评分: 良好');
    await tester.pumpAndSettle();

    expect(find.text('当前评分: 轻松'), findsNothing);
    expect(find.text('当前评分: 良好'), findsOneWidget);
    expect(find.textContaining('下次复习: ${goodItem.scheduledDays}天后', findRichText: true),
        findsOneWidget);
  });

  testWidgets('已作答时点「再学学」：评分原样带进详情页，一个字都不改', (tester) async {
    final (testWord, mockResult) = _createTestData(stepIndex: 1);
    final fsrs = FSRS();
    // 本次作答已经答错（忘记）
    final state = _answeredGoodState(testWord, mockResult, fsrs.init(FsrsRating.again))
        .copyWith(lastFsrsRating: FsrsRating.again, isScorePassed: false);
    final notifier = MockBdcNotifierForPanel(state, mockHasSeenAnswer: true);
    await pumpPage(tester, notifier);

    await tester.tap(find.byKey(const Key('bdc_study_again')));
    await tester.pumpAndSettle();

    expect(notifier.capturedDetailRating, FsrsRating.again,
        reason: '已作答时「再学学」不得把评分提成良好：'
            '那会让当天首条评分翻盘、轨道从答错组跳到答对组');
    expect(notifier.capturedDetailIsWrong, isTrue,
        reason: '详情页必须知道这是答错的词，不能当成答对处理');
  });

  testWidgets('未作答点「再学学」：相当于良好', (tester) async {
    final (testWord, mockResult) = _createTestData();
    final notifier = MockBdcNotifierForPanel(
      const BdcState().copyWith(
        dataLoaded: true,
        word: testWord,
        currentGetWordResult: mockResult,
        wordWrapper: WordWrapper(testWord, null),
        studyStep: StudyStep.en2Ch.json,
        showAnswerButtons: true,
        canLeaveCurrWord: false,
        hasFinishedAnswering: false,
      ),
      mockHasSeenAnswer: false,
    );
    await pumpPage(tester, notifier);

    await tester.tap(find.byKey(const Key('bdc_study_again')));
    await tester.pumpAndSettle();

    expect(notifier.capturedDetailRating, FsrsRating.good,
        reason: '没有任何作答事实时，「再学学」就是良好');
    expect(notifier.capturedDetailIsWrong, isFalse);
  });

  /// 「再学学」按钮下方那条横杠（指示光条）的颜色 —— 它是"点了会拿到什么评分"的预告。
  Color studyAgainIndicatorColor(WidgetTester tester) {
    final bars = tester
        .widgetList<Container>(find.descendant(
          of: find.byKey(const Key('bdc_study_again')),
          matching: find.byType(Container),
        ))
        .where((c) =>
            c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).boxShadow != null)
        .toList();
    expect(bars, hasLength(1), reason: '「再学学」下方应有且只有一条横杠');
    return (bars.single.decoration! as BoxDecoration).color!;
  }

  testWidgets('「再学学」横杠颜色＝点了会拿到的评分色：未作答时是良好色', (tester) async {
    final (testWord, mockResult) = _createTestData();
    final notifier = MockBdcNotifierForPanel(
      const BdcState().copyWith(
        dataLoaded: true,
        word: testWord,
        currentGetWordResult: mockResult,
        wordWrapper: WordWrapper(testWord, null),
        studyStep: StudyStep.en2Ch.json,
        showAnswerButtons: true,
        canLeaveCurrWord: false,
        hasFinishedAnswering: false,
      ),
      mockHasSeenAnswer: false,
    );
    await pumpPage(tester, notifier);

    expect(studyAgainIndicatorColor(tester), FsrsRating.good.colorWithDark(false),
        reason: '没作答时点「再学学」会拿到良好，横杠必须是良好色');
  });

  testWidgets('「再学学」横杠颜色跟随已作答评分，且改判后立刻变化', (tester) async {
    final (testWord, mockResult) = _createTestData(stepIndex: 1);
    final fsrs = FSRS();
    // 已答对（轻松）→ 横杠＝轻松色，因为点「再学学」会保留轻松
    final state = _answeredGoodState(testWord, mockResult, fsrs.init(FsrsRating.easy))
        .copyWith(lastFsrsRating: FsrsRating.easy);
    final notifier = MockBdcNotifierForPanel(state, mockHasSeenAnswer: true);
    await pumpPage(tester, notifier);
    expect(studyAgainIndicatorColor(tester), FsrsRating.easy.colorWithDark(false),
        reason: '已作答时点「再学学」保留原评分，横杠要显示那个评分的颜色');

    // 改判为忘记（点「不认识」/选错了答案）→ 横杠必须立刻变成忘记色。
    // 改判不进顶层刷新签名、学习页不会整页重建，只有单独订阅才刷得到这一条 ——
    // 刷不到就等于给了用户一个错预告。
    notifier.applyReGrade(FsrsRating.again, fsrsItem: fsrs.init(FsrsRating.again));
    await tester.pumpAndSettle();
    expect(studyAgainIndicatorColor(tester), FsrsRating.again.colorWithDark(false),
        reason: '改判后横杠颜色必须跟着变：颜色代表将要落到的评分');
  });

  testWidgets('巩固环节（stepIndex=1）的评分行必须标成「本次评分」，不得冒充「测评结果」', (tester) async {
    final (testWord, mockResult) = _createTestData(stepIndex: 1);
    final fsrs = FSRS();
    final notifier = MockBdcNotifierForPanel(
      _answeredGoodState(testWord, mockResult, fsrs.init(FsrsRating.good))
          .copyWith(todayLatestRating: FsrsRating.easy, todayLatestScheduledDays: 16),
      mockHasSeenAnswer: true,
      mockHasUnsubmittedAnswer: true,
    );
    await pumpPage(tester, notifier);

    expect(find.text('本次评分: 良好'), findsOneWidget,
        reason: '巩固环节这一行是"本次作答"的评分与推算，标签必须如实');
    expect(find.text('测评结果: 良好'), findsNothing,
        reason: '不得把巩固环节的推算标成测评结果（用户会对着它改错对象）');
  });

  testWidgets('巩固环节未作答时，那一行显示「当前评分」＝当天最近一次计分作答，不得取历史最新一条', (tester) async {
    final (testWord, mockResult) = _createTestData(stepIndex: 1);
    final notifier = MockBdcNotifierForPanel(
      const BdcState().copyWith(
        dataLoaded: true,
        word: testWord,
        currentGetWordResult: mockResult,
        wordWrapper: WordWrapper(testWord, null),
        studyStep: StudyStep.en2Ch.json,
        showAnswerButtons: true,
        canLeaveCurrWord: false,
        hasFinishedAnswering: false,
        // 当天最近一次计分作答＝测评的轻松 · 16 天（也正是改评分要改的那条）
        todayLatestRating: FsrsRating.easy,
        todayLatestScheduledDays: 16,
      ),
      mockHasSeenAnswer: false,
    );
    // 历史流水里最新一条是"模糊 · 13 天"（今天更晚那次巩固的结果）
    notifier.learningHistoryFuture = Future.value([
      LearningLog(
        id: 'log_latest',
        userId: 'user1',
        wordId: 'w_apple',
        rating: FsrsRating.hard.value,
        stability: 13.177992997479922,
        difficulty: 4.318881718775723,
        elapsedDays: 0,
        scheduledDays: 13,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ),
      LearningLog(
        id: 'log_assess',
        userId: 'user1',
        wordId: 'w_apple',
        rating: FsrsRating.easy.value,
        stability: 15.69105,
        difficulty: 3.2245015893713678,
        elapsedDays: 0,
        scheduledDays: 16,
        createTime: DateTime.now().subtract(const Duration(minutes: 10)),
        updateTime: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
    ]);
    await pumpPage(tester, notifier);

    expect(find.text('当前评分: 轻松'), findsOneWidget,
        reason: '这一行是"当天最近一次计分作答"（也正是改评分要改的那条）');
    expect(find.textContaining('下次复习: 16天后', findRichText: true), findsOneWidget,
        reason: '天数必须跟着那条记录走');
    expect(find.text('当前评分: 模糊'), findsNothing,
        reason: '不得拿历史最新一条（后来的巩固结果）冒充当前评分');
    expect(find.textContaining('下次复习: 13天后', findRichText: true), findsNothing);
  });

  testWidgets('回看已作答的巩固环节：那一行显示的是当天最近一次计分作答，点它就改它', (tester) async {
    // 实测路径：新词测评轻松(16天) → 巩固环节作答良好 → 点「下一词」落库 → 点「回看」。
    // 面板那一行显示的必须是"当天最近一次计分作答"（巩固那条），点它改的也就是那一条。
    // 绝不能显示成"测评结果"再去改测评首条 —— 那样用户对着"良好"改回"良好"，
    // 天数会从 16 天变成 init(良好) 的 3 天（线上就是这么被发现的）。
    final (testWord, mockResult) = _createTestData(stepIndex: 1);
    final fsrs = FSRS();
    // 丙口径下巩固环节的"良好"不改动记忆参数，那条快照的天数仍是 16 天
    final consolidateSnapshot = fsrs.init(FsrsRating.easy);
    final notifier = MockBdcNotifierForPanel(
      _answeredGoodState(testWord, mockResult, consolidateSnapshot).copyWith(
        historyIndex: 1,
        todayLatestRating: FsrsRating.good,
        todayLatestScheduledDays: 16,
        todayLatestLogIndex: 2,
      ),
      mockHasSeenAnswer: true,
      mockHasUnsubmittedAnswer: false,
    );
    await pumpPage(tester, notifier);

    expect(find.text('当前评分: 良好'), findsOneWidget,
        reason: '回看时那一行是当天最近一次计分作答（巩固那条），改评分改的就是它');
    expect(find.text('当前评分: 轻松'), findsNothing,
        reason: '不得把最近一次计分作答显示成测评的轻松 —— 那会让用户改到测评首条上（所见非所改）');
    expect(find.textContaining('下次复习: 16天后', findRichText: true), findsOneWidget,
        reason: '天数跟着那一条记录走');
  });

  testWidgets('回看历史时不显示流程坐标行：本组进度与「本环节重测」都不得出现', (tester) async {
    // 线上反馈：某个词刚点过「不认识」，切到下一个词后再回看它，它被标成「本环节重测」。
    // 那条流程坐标描述的是"这个词现在排在本组本环节的第几位"，而回看展示的是那一次呈现，
    // 两者不是一回事 —— 回看时整行都不显示。
    final (testWord, mockResult) = _createTestData(stepIndex: 1);
    final notifier = MockBdcNotifierForPanel(
      _answeredGoodState(testWord, mockResult, FSRS().init(FsrsRating.good))
          .copyWith(
        historyIndex: 0,
        groupStepNo: 1,
        groupStepPosition: 1,
        groupStepTotal: 3,
        groupStepTrackName: '新词答对',
        isGroupStepRetry: true,
      ),
      mockHasSeenAnswer: true,
    );
    await pumpPage(tester, notifier);

    expect(find.textContaining('本环节重测'), findsNothing,
        reason: '回看历史不得标「本环节重测」——那会让人以为回看就等于重测');
    expect(find.textContaining('新词答对'), findsNothing,
        reason: '回看历史也不显示本组本环节的排队坐标');
  });

  testWidgets('学习流程里照常显示流程坐标行（回看才隐藏）', (tester) async {
    final (testWord, mockResult) = _createTestData(stepIndex: 1);
    final notifier = MockBdcNotifierForPanel(
      _answeredGoodState(testWord, mockResult, FSRS().init(FsrsRating.good))
          .copyWith(
        groupStepNo: 1,
        groupStepPosition: 1,
        groupStepTotal: 3,
        groupStepTrackName: '新词答对',
        isGroupStepRetry: true,
      ),
      mockHasSeenAnswer: true,
    );
    await pumpPage(tester, notifier);

    expect(find.textContaining('本环节重测'), findsOneWidget,
        reason: '正常学习时这个词确实在重测，必须标出来');
    expect(find.textContaining('新词答对'), findsOneWidget);
  });
}
