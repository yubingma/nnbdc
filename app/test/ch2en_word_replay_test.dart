import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/bdc/bdc.dart';
import 'package:nnbdc/page/bdc/providers/answer_mode.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:provider/provider.dart' as provider;

/// 汉译英（Ch2En）答对后只有一次自动播放，用户想主动再听一遍却没有入口：
/// 题面只有中文释义（不能给发音，等于报答案），说档和写档的答案区也都不可点。
/// 所以答案揭晓后必须在答题卡上出现一颗「再听一遍」的小喇叭。
class MockBdcNotifier extends BdcNotifier {
  final BdcState initialState;
  MockBdcNotifier(this.initialState);

  @override
  BdcState build() {
    return initialState;
  }

  @override
  Future<void> loadData(BuildContext? context, {bool isAutoTest = false}) async {}
}

(WordVo, GetWordResult) _createTestData() {
  final testWord = WordVo.c2('testword')
    ..id = 'w_test'
    ..setMeaningStr('n. 测试词');
  testWord.meaningItems = [
    MeaningItemVo('mi_1', 'n.', '测试词', null, null, []),
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
    1, // stepIndex > 0：汉译英（巩固）环节
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

Widget _buildPage(BdcState state) {
  return provider.ChangeNotifierProvider<DarkMode>(
    create: (_) => DarkMode(),
    child: ProviderScope(
      overrides: [
        bdcNotifierProvider.overrideWith(() => MockBdcNotifier(state)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: BdcPage(),
        ),
      ),
    ),
  );
}

const Key _replayKey = Key('bdc_replay_word_sound');

void main() {
  setUp(() {
    PlatformUtils.asrSupportedOverride = true;
    PlatformUtils.englishAsrSupportedOverride = true;
  });

  tearDown(() {
    PlatformUtils.asrSupportedOverride = null;
    PlatformUtils.englishAsrSupportedOverride = null;
  });

  testWidgets('汉译英说档：答题前不能出现「再听一遍」，否则等于报答案', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    await tester.pumpWidget(_buildPage(const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.ch2En.json,
      answerMode: AnswerMode.speak,
      hasFinishedAnswering: false,
    )));
    await tester.pump();

    expect(find.byKey(_replayKey), findsNothing,
        reason: '汉译英题面只有中文释义，答题前给发音等于把答案念出来');
  });

  testWidgets('汉译英说档：答对后出现「再听一遍」小喇叭', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    await tester.pumpWidget(_buildPage(const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.ch2En.json,
      answerMode: AnswerMode.speak,
      hasFinishedAnswering: true,
      isScorePassed: true,
    )));
    await tester.pump();

    expect(find.byKey(_replayKey), findsOneWidget,
        reason: '答对后要能主动点一下再听一遍单词发音');
  });

  testWidgets('汉译英写档：答题前不能出现「再听一遍」', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    await tester.pumpWidget(_buildPage(const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.ch2En.json,
      answerMode: AnswerMode.write,
      // 键盘态让写档用输入行，不创建内嵌手写板（测试环境没有手写识别模型）
      isKeyboardVisible: true,
      hasFinishedAnswering: false,
    )));
    await tester.pump();

    expect(find.byKey(_replayKey), findsNothing,
        reason: '写档答题前同样不能给出发音，答案还没揭晓');
  });

  testWidgets('汉译英写档：答对后出现「再听一遍」小喇叭', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    await tester.pumpWidget(_buildPage(const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.ch2En.json,
      answerMode: AnswerMode.write,
      isKeyboardVisible: true,
      hasFinishedAnswering: true,
      isScorePassed: true,
    )));
    await tester.pump();

    // 写档答对后输入行原地换成「正确答案行」，确认渲染的确实是写档那一档
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byKey(_replayKey), findsOneWidget,
        reason: '写档答对后答案已经揭晓，也要能主动再听一遍');
  });
}
