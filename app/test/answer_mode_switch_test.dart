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
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/widget/handwriting_board.dart';
import 'package:provider/provider.dart' as provider;

/// 只把这一页用得上的 ASR 方法做掉，其余交给 noSuchMethod
class MockAsr implements Asr {
  @override
  AsrState get state => AsrState.initialized;

  @override
  bool get isPreloaded => true;

  @override
  bool get permissionGranted => true;

  @override
  set permissionGranted(bool value) {}

  @override
  AsrLanguage? get currentLanguage => null;

  @override
  void addStateListener(Function(AsrState) listener) {}

  @override
  void removeStateListener(Function(AsrState) listener) {}

  @override
  Future<void> initAsr(void Function(dynamic)? asrListener) async {}

  @override
  Future<void> startAsr(AsrLanguage language,
      {List<String>? phrases, bool playHintSound = true}) async {}

  @override
  Future<String?> stopAsr() async => null;

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> updateLanguage(AsrLanguage language) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockBdcNotifier extends BdcNotifier {
  final BdcState initialState;
  MockBdcNotifier(this.initialState);

  @override
  BdcState build() {
    this.asr = ref.watch(asrProvider);
    return initialState;
  }

  @override
  Future<void> loadData(BuildContext? context, {bool isAutoTest = false}) async {}
}

(WordVo, GetWordResult) _createTestData() {
  final WordVo testWord = WordVo.c2('apple')..id = 'w_apple';
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
    [],
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

BdcState _stateWith(
  WordVo word,
  GetWordResult result, {
  required String studyStep,
  required AnswerMode answerMode,
}) {
  return const BdcState().copyWith(
    dataLoaded: true,
    word: word,
    wordWrapper: WordWrapper(word, null),
    currentGetWordResult: result,
    studyStep: studyStep,
    answerMode: answerMode,
  );
}

Future<void> _pumpPage(WidgetTester tester, BdcState state) async {
  final mockAsr = MockAsr();
  StudyAudioSessionController.instance.debugSetAsrForTesting(mockAsr);
  await tester.pumpWidget(
    provider.ChangeNotifierProvider<DarkMode>(
      create: (_) => DarkMode(),
      child: ProviderScope(
        overrides: [
          asrProvider.overrideWithValue(mockAsr),
          bdcNotifierProvider.overrideWith(() => MockBdcNotifier(state)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BdcPage()),
        ),
      ),
    ),
  );
  await tester.pump();
  // 写档的输入框 autofocus 在下一帧才真正拿到焦点，而焦点变化会触发一次重建
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() {
    PlatformUtils.asrSupportedOverride = true;
    PlatformUtils.englishAsrSupportedOverride = true;
  });

  tearDown(() {
    PlatformUtils.asrSupportedOverride = null;
    PlatformUtils.englishAsrSupportedOverride = null;
  });

  testWidgets('单词环节三档都摆在答题卡上，默认「说」', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
            studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.speak));

    expect(find.byKey(const Key('bdc_answer_mode_write')), findsOneWidget);
    expect(find.byKey(const Key('bdc_answer_mode_speak')), findsOneWidget);
    expect(find.byKey(const Key('bdc_answer_mode_choose')), findsOneWidget);
    // 说档：题面是"说"，写面板不出现
    expect(find.text('请说出中文释义：'), findsOneWidget);
    expect(find.byKey(const Key('bdc_typing_input')), findsNothing);
  });

  testWidgets('切到「写」：英译汉直接是键盘打字面板，不再"请说"', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
            studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.speak));

    await tester.tap(find.byKey(const Key('bdc_answer_mode_write')));
    await tester.pumpAndSettle();

    // 顶栏说的是"写"而不是"说"
    expect(find.text('请写出中文释义：'), findsOneWidget);
    expect(find.text('请说出中文释义：'), findsNothing);
    // 聚焦的是页面里的打字输入框，而不是被抢进全屏拼写板
    expect(find.byKey(const Key('bdc_typing_input')), findsOneWidget);
    expect(find.byType(HandwritingBoard), findsNothing);
    // 中文释义是手打的，只能显式提交
    expect(find.text('提交'), findsOneWidget);
  });

  testWidgets('写档：汉译英是拼写面板，没有提交按钮', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
            studyStep: StudyStep.ch2En.json, answerMode: AnswerMode.write));

    expect(find.text('请拼写单词：'), findsOneWidget);
    expect(find.text('请说出单词发音：'), findsNothing);
    expect(find.byKey(const Key('bdc_typing_input')), findsOneWidget);
    expect(find.byType(HandwritingBoard), findsNothing);
    // 英文拼写打对即判，不需要"提交"
    expect(find.text('提交'), findsNothing);
  });

  testWidgets('例句环节只有 说/选 两档，没有「写」', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
            studyStep: StudyStep.enSentence2Ch.json,
            answerMode: AnswerMode.choose));

    expect(find.text('说'), findsOneWidget);
    expect(find.text('选'), findsOneWidget);
    expect(find.byKey(const Key('bdc_answer_mode_write')), findsNothing);
  });
}
