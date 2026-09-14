import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/bdc/bdc.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/state.dart';
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
  });
}
