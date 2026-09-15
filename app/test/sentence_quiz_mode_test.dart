import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/bdc/bdc.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:provider/provider.dart' as provider;

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
    ..setMeaningStr('n. 测试词\nv. 考验');
  final sentenceVo = SentenceVo(
    's_1',
    'This is a testword sentence.',
    '这是一个测试词例句。',
    null,
    'n.',
    'tts',
    0,
    0,
    UserVo.c2('author1'),
  );
  testWord.meaningItems = [
    MeaningItemVo('mi_1', 'n.', '测试词', null, null, [sentenceVo]),
    MeaningItemVo('mi_2', 'v.', '考验', null, null, []),
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

  final otherWord1 = WordVo.c2('option1')..setMeaningStr('n. 选项一');
  final otherWord2 = WordVo.c2('option2')..setMeaningStr('n. 选项二');
  final otherWord3 = WordVo.c2('option3')..setMeaningStr('n. 选项三');

  final mockGetWordResult = GetWordResult(
    testLw,
    0,
    [otherWord1, otherWord2, otherWord3],
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

void main() {
  setUp(() {
    PlatformUtils.asrSupportedOverride = true;
    PlatformUtils.englishAsrSupportedOverride = true;
  });

  tearDown(() {
    PlatformUtils.asrSupportedOverride = null;
    PlatformUtils.englishAsrSupportedOverride = null;
  });

  testWidgets('例句英译汉(EnSentence2Ch)题目区显示英文拼写与选择题选项', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    final enState = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.enSentence2Ch.json,
      tabIndex: 1, // 选择题模式
      words: [testWord, ...mockGetWordResult.otherWords!],
      correctAnswerIndex: 1,
    );

    await tester.pumpWidget(
      provider.ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: ProviderScope(
          overrides: [
            bdcNotifierProvider.overrideWith(() => MockBdcNotifier(enState)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BdcPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // 验证题目区展示了目标单词英文拼写
    final spellFinder = find.byKey(const Key('en_sentence_word_spell'));
    expect(spellFinder, findsOneWidget);
    expect(tester.widget<Text>(spellFinder).data, 'testword');

    // 验证展示了例句内容
    expect(find.textContaining('This is a'), findsOneWidget);

    // 验证选择题模式下切换按钮文案为「说中文」（非「说释义」）
    expect(find.text('说中文'), findsOneWidget);
    expect(find.text('说释义'), findsNothing);
  });

  testWidgets('例句汉译英(ChSentence2En)题目区展示中文例句与单行横滑释义', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    final chState = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.chSentence2En.json,
      tabIndex: 1, // 选择题模式
      words: [testWord, ...mockGetWordResult.otherWords!],
      correctAnswerIndex: 1,
    );

    await tester.pumpWidget(
      provider.ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: ProviderScope(
          overrides: [
            bdcNotifierProvider.overrideWith(() => MockBdcNotifier(chState)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BdcPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // 验证题目区展示了中文例句
    expect(find.textContaining('这是一个测试词例句。'), findsOneWidget);

    // 验证展示了单行水平滚动的单词释义组件
    final horizontalScrollFinder = find.byWidgetPredicate(
      (widget) => widget is SingleChildScrollView && widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontalScrollFinder, findsAtLeastNWidgets(1));

    // 验证展示了单词释义项（词性与释义内容）
    expect(find.textContaining('测试词'), findsWidgets);
    expect(find.textContaining('考验'), findsWidgets);

    // 验证选择题模式下切换按钮文案为「说英文」（非「说发音」）
    expect(find.text('说英文'), findsOneWidget);
    expect(find.text('说发音'), findsNothing);
  });

  testWidgets('例句模式文案彻底区分于单词模式（语音模式未作答状态）', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    final enStateUnanswered = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.enSentence2Ch.json,
      tabIndex: 0, // 语音模式
      hasFinishedAnswering: false,
      words: [testWord, ...mockGetWordResult.otherWords!],
      correctAnswerIndex: 1,
    );

    await tester.pumpWidget(
      provider.ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: ProviderScope(
          overrides: [
            bdcNotifierProvider.overrideWith(() => MockBdcNotifier(enStateUnanswered)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BdcPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 顶栏提示必须为「请说出例句翻译：」，绝不能是「请说出中文释义：」
    expect(find.text('请说出例句翻译：'), findsOneWidget);
    expect(find.text('请说出中文释义：'), findsNothing);
    // 输入框占位提示为「请按住下方按钮，说出例句翻译」
    expect(find.text('请按住下方按钮，说出例句翻译'), findsOneWidget);
    // PTT 按钮在未作答时显示为「按住说话」
    expect(find.text('按住说话'), findsOneWidget);
  });

  testWidgets('例句模式下已完成答题/看答案状态PTT按钮常驻且变为「按住练习」', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    final enStateAnswered = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.enSentence2Ch.json,
      tabIndex: 0, // 语音模式
      hasFinishedAnswering: true,
      canLeaveCurrWord: true,
      words: [testWord, ...mockGetWordResult.otherWords!],
      correctAnswerIndex: 1,
    );

    await tester.pumpWidget(
      provider.ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: ProviderScope(
          overrides: [
            bdcNotifierProvider.overrideWith(() => MockBdcNotifier(enStateAnswered)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BdcPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 核心验证：答完题后 PTT 按钮绝不能消失留下空白，应常驻且变为「按住练习」
    expect(find.text('按住练习'), findsOneWidget);
  });

  testWidgets('例句模式能正确记忆选择题与说模式偏好（isSentenceSelectModePreferred）', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    // 初始状态：例句环节偏好选择题
    final enStatePreferredSelect = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.enSentence2Ch.json,
      tabIndex: 1, // 当前在选择题模式
      isSentenceSelectModePreferred: true,
      isSelectModePreferred: false, // 单词模式偏好说，两者互不干扰
      words: [testWord, ...mockGetWordResult.otherWords!],
      correctAnswerIndex: 1,
    );

    final mockNotifier = MockBdcNotifier(enStatePreferredSelect);

    await tester.pumpWidget(
      provider.ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: ProviderScope(
          overrides: [
            bdcNotifierProvider.overrideWith(() => mockNotifier),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BdcPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 验证当前显示选择题切换按钮「说中文」
    expect(find.text('说中文'), findsOneWidget);

    // 模拟用户在例句模式下切换为语音 Tab（index 0）
    mockNotifier.updateTabIndex(0);
    expect(mockNotifier.state.isSentenceSelectModePreferred, false);
    // 单词模式偏好保持不变
    expect(mockNotifier.state.isSelectModePreferred, false);

    // 模拟用户在例句模式下切换回选择题 Tab（index 1）
    mockNotifier.updateTabIndex(1);
    expect(mockNotifier.state.isSentenceSelectModePreferred, true);
  });
}

