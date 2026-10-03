import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/bdc/bdc.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/fsrs.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart' as provider;

/// 评分面板（测评结果 + 下次复习天数）的刷新口径测试。
///
/// 面板显示的数据（lastFsrsRating / fsrsItem / assessmentRating）刻意不进
/// [BdcStateUiSignature]（改判时不让学习页整页重建、与详情页转场首帧抢帧），
/// 因此面板必须自己订阅这些字段（见 BdcPageState 的 `_buildLiveFsrsResultPanel`）。
/// 这里锁死"改判后立刻所见即所得"：界面上的评分与下次复习天数必须等于最后表态。
class MockBdcNotifierForPanel extends BdcNotifier {
  final BdcState initialState;
  bool mockHasSeenAnswer;

  MockBdcNotifierForPanel(this.initialState, {this.mockHasSeenAnswer = false});

  @override
  BdcState build() => initialState;

  @override
  bool get hasSeenAnswer => mockHasSeenAnswer;

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

  @override
  Future<void> loadData(BuildContext? context, {bool isAutoTest = false}) async {}
}

(WordVo, GetWordResult) _createTestData() {
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
    testLw, 0, null, [1, 10], null, false, false, [], [], [], null, [], [], [], false, false,
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

    expect(find.text('测评结果: 良好'), findsOneWidget, reason: '答对后面板显示良好');

    // 用户改点「不认识」：评分被改判为忘记（不点「下一词」，直接进详情页再返回）
    final againItem = fsrs.init(FsrsRating.again);
    notifier.applyReGrade(FsrsRating.again,
        fsrsItem: againItem, reason: '主动点击了不再认识，评分: 忘记');
    await tester.pumpAndSettle();

    expect(find.text('测评结果: 良好'), findsNothing,
        reason: '最后表态是「不认识」＝忘记，界面不得继续显示良好（所见即所得）');
    expect(find.text('测评结果: 忘记'), findsOneWidget);
    expect(find.textContaining('下次复习: ${againItem.scheduledDays}天后', findRichText: true),
        findsOneWidget,
        reason: '评分改了，面板上的下次复习天数必须按新评分重算');
  });

  testWidgets('答对(轻松)后改判「再学学」：面板必须跟着回到良好', (tester) async {
    final (testWord, mockResult) = _createTestData();
    final fsrs = FSRS();
    final easyItem = fsrs.init(FsrsRating.easy);
    final state = _answeredGoodState(testWord, mockResult, easyItem)
        .copyWith(lastFsrsRating: FsrsRating.easy);
    final notifier = MockBdcNotifierForPanel(state, mockHasSeenAnswer: true);
    await pumpPage(tester, notifier);

    expect(find.text('测评结果: 轻松'), findsOneWidget);

    final goodItem = fsrs.init(FsrsRating.good);
    notifier.applyReGrade(FsrsRating.good,
        fsrsItem: goodItem, reason: '主动点击了再学学，评分: 良好');
    await tester.pumpAndSettle();

    expect(find.text('测评结果: 轻松'), findsNothing);
    expect(find.text('测评结果: 良好'), findsOneWidget);
    expect(find.textContaining('下次复习: ${goodItem.scheduledDays}天后', findRichText: true),
        findsOneWidget);
  });
}
