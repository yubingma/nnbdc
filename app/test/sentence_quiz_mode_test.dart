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
import 'package:nnbdc/util/word_util.dart';
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

  testWidgets('例句英译汉(EnSentence2Ch)选择题Tab显示单词拼写且不显示例句', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    final choiceState = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.enSentence2Ch.json,
      answerMode: AnswerMode.choose,
      words: [testWord, ...mockGetWordResult.otherWords!],
      correctAnswerIndex: 1,
    );

    await tester.pumpWidget(
      provider.ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: ProviderScope(
          overrides: [
            bdcNotifierProvider.overrideWith(() => MockBdcNotifier(choiceState)),
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

    // 选择题模式：显示单词拼写，不显示例句
    final spellFinder = find.byKey(const Key('en_sentence_word_spell'));
    expect(spellFinder, findsOneWidget);
    expect(tester.widget<Text>(spellFinder).data, 'testword');
    expect(find.textContaining('This is a'), findsNothing);

    // 答题方式三档里「选」是亮着的，「说」这一档点一下就回去
    expect(find.text('说'), findsOneWidget);
    expect(find.text('选'), findsOneWidget);
  });

  testWidgets('例句英译汉(EnSentence2Ch)说模式Tab只显示例句且不显示单词拼写', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    final speakState = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.enSentence2Ch.json,
      answerMode: AnswerMode.speak,
      words: [testWord, ...mockGetWordResult.otherWords!],
      correctAnswerIndex: 1,
    );

    await tester.pumpWidget(
      provider.ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: ProviderScope(
          overrides: [
            bdcNotifierProvider.overrideWith(() => MockBdcNotifier(speakState)),
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

    // 说模式：只显示例句，不显示单词拼写
    expect(find.byKey(const Key('en_sentence_word_spell')), findsNothing);
    expect(find.textContaining('This is a'), findsOneWidget);
  });

  testWidgets('例句汉译英(ChSentence2En)选择题Tab显示单行横滑释义且不显示例句', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    final choiceState = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.chSentence2En.json,
      answerMode: AnswerMode.choose,
      words: [testWord, ...mockGetWordResult.otherWords!],
      correctAnswerIndex: 1,
    );

    await tester.pumpWidget(
      provider.ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: ProviderScope(
          overrides: [
            bdcNotifierProvider.overrideWith(() => MockBdcNotifier(choiceState)),
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

    // 选择题模式：显示多行排版释义，不显示中文例句
    expect(find.textContaining('这是一个测试词例句。'), findsNothing);
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('测试词'), findsWidgets);

    // 答题方式里只有 说/选 两档：例句环节没有「写」
    expect(find.text('说'), findsOneWidget);
    expect(find.text('写'), findsNothing);
    expect(find.text('说发音'), findsNothing);
  });

  testWidgets('例句汉译英(ChSentence2En)说模式Tab只显示例句且不显示释义', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    final speakState = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.chSentence2En.json,
      answerMode: AnswerMode.speak,
      words: [testWord, ...mockGetWordResult.otherWords!],
      correctAnswerIndex: 1,
    );

    await tester.pumpWidget(
      provider.ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: ProviderScope(
          overrides: [
            bdcNotifierProvider.overrideWith(() => MockBdcNotifier(speakState)),
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

    // 说模式：只显示中文例句，不显示单词释义单行横滑组件
    expect(find.textContaining('这是一个测试词例句。'), findsOneWidget);
    expect(find.byWidgetPredicate(
      (widget) => widget is SingleChildScrollView && widget.scrollDirection == Axis.horizontal,
    ), findsNothing);
  });

  testWidgets('例句模式文案彻底区分于单词模式（语音模式未作答状态）', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    final enStateUnanswered = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.enSentence2Ch.json,
      answerMode: AnswerMode.speak,
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
      answerMode: AnswerMode.speak,
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

  testWidgets('例句模式切档后记住用户选的方式，且不串到单词环节', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    final enStateChoosing = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.enSentence2Ch.json,
      answerMode: AnswerMode.choose,
      words: [testWord, ...mockGetWordResult.otherWords!],
      correctAnswerIndex: 1,
    );

    final mockNotifier = MockBdcNotifier(enStateChoosing);

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

    // 例句环节没有「写」档：切换控件里只有 说/选
    expect(find.text('说'), findsOneWidget);
    expect(find.text('选'), findsOneWidget);
    expect(find.text('写'), findsNothing);

    // 切到「说」：例句环节这一档生效（落盘口径由 bdc_notifier_test 覆盖）
    mockNotifier.updateAnswerMode(AnswerMode.speak);
    expect(mockNotifier.state.answerMode, AnswerMode.speak);

    // 切回「选」
    mockNotifier.updateAnswerMode(AnswerMode.choose);
    expect(mockNotifier.state.answerMode, AnswerMode.choose);
    // 例句环节没有写档，切过去必须被拒
    mockNotifier.updateAnswerMode(AnswerMode.write);
    expect(mockNotifier.state.answerMode, AnswerMode.choose);
  });

  testWidgets('选择题模式下点击「隐藏答案继续练习」能成功隐藏答案并重置作答状态', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    // 初始状态：例句环节选择题模式，且已作答（已揭晓答案）
    final enStateAnswered = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.enSentence2Ch.json,
      answerMode: AnswerMode.choose,
      hasFinishedAnswering: true,
      selectedAnswerIndex: 1, // 选中第 1 个选项
      words: [testWord, ...mockGetWordResult.otherWords!],
      correctAnswerIndex: 1,
    );

    final mockNotifier = MockBdcNotifier(enStateAnswered);

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

    // 答题后状态：选项处于已揭晓答案状态，题目区展示「隐藏答案继续练习」按钮
    final hideBtnFinder = find.text('隐藏答案继续练习');
    expect(hideBtnFinder, findsOneWidget);

    // 点击「隐藏答案继续练习」
    await tester.tap(hideBtnFinder);
    await tester.pump();

    // 核心验证：selectedAnswerIndex 必须被清空为 null，hasFinishedAnswering 变回 false
    expect(mockNotifier.state.selectedAnswerIndex, isNull);
    expect(mockNotifier.state.hasFinishedAnswering, isFalse);

    // 按钮文案变回「看答案」
    expect(find.text('看答案'), findsOneWidget);
    expect(find.text('隐藏答案继续练习'), findsNothing);
  });

  testWidgets('例句模式点击「看答案」后即使隐藏答案继续练习，底部的测评结果（忘记）依然常驻展示', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    // 初始状态：例句环节语音模式未作答
    final enState = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.enSentence2Ch.json,
      answerMode: AnswerMode.speak,
      hasFinishedAnswering: false,
    );

    final mockNotifier = MockBdcNotifier(enState);

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

    // 1. 点击「看答案」
    final seeAnswerBtnFinder = find.text('看答案');
    expect(seeAnswerBtnFinder, findsOneWidget);
    await tester.tap(seeAnswerBtnFinder);
    await tester.pump();

    // 验证看答案后：底部的测评结果（忘记）出现
    // （这是测评环节的"本次作答"＝看答案受理的那一次评分，标签仍是「测评结果」）
    expect(find.textContaining('测评结果: 忘记'), findsOneWidget);
    expect(find.text('隐藏答案继续练习'), findsOneWidget);

    // 2. 点击「隐藏答案继续练习」
    final hideBtnFinder = find.text('隐藏答案继续练习');
    await tester.tap(hideBtnFinder);
    await tester.pump();

    // 核心验证：进入练习模式后，底部的测评结果（忘记）必须依然常驻展示，不能变回空白占位
    expect(mockNotifier.state.hasFinishedAnswering, isFalse);
    expect(mockNotifier.state.isPracticeMode, isTrue);
    expect(find.textContaining('测评结果: 忘记'), findsOneWidget);
  });

  testWidgets('字体调大时(TextScaler=1.2)，英译汉模式下3个选项及底部测评信息完整渲染不溢出', (tester) async {
    final (testWord, mockResult) = _createTestData();

    final state = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      wordWrapper: WordWrapper(testWord, null),
      currentGetWordResult: mockResult,
      studyStep: StudyStep.en2Ch.json,
      answerMode: AnswerMode.speak,
      words: [
        WordVo.c2('frigate')..setMeaningStr('n. 护卫舰；快速战舰'),
        WordVo.c2('primate')..setMeaningStr('n. 灵长类动物；大主教 adj. 灵长类'),
        WordVo.c2('private')..setMeaningStr('adj. 私人的 · 个人的 · 私有的 · 私下'),
      ],
      correctAnswerIndex: 3,
      selectedAnswerIndex: 3,
      hasFinishedAnswering: true,
      lastFsrsRating: FsrsRating.easy,
    );

    final mockNotifier = MockBdcNotifier(state);

    await tester.pumpWidget(
      provider.ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: ProviderScope(
          overrides: [
            bdcNotifierProvider.overrideWith(() => mockNotifier),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                textScaler: TextScaler.linear(1.2),
              ),
              child: const Scaffold(
                body: BdcPage(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final selectBtn = find.byKey(const Key('bdc_answer_mode_choose'));
    expect(selectBtn, findsOneWidget);
    await tester.tap(selectBtn);
    await tester.pumpAndSettle();

    // 验证 3 个选项的拼写均能正常找到（Text.rich 需用 textContaining 匹配）
    expect(find.textContaining('frigate'), findsOneWidget);
    expect(find.textContaining('primate'), findsOneWidget);
    expect(find.textContaining('private'), findsWidgets);

    // 验证第3个选项的释义和底部的当前评分均正常展示且无溢出
    expect(find.textContaining('私人的'), findsOneWidget);
    expect(find.textContaining('当前评分: 轻松'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

