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

/// 汉译英（Ch2En）环节的题目是**中文释义**，所以"这个词今天刚答错过"的红色提示
/// 必须落在释义上 —— 与英译汉环节把英文拼写标红同一口径。
///
/// 用户反馈：在答对组的汉译英环节对一个之前答对的词点「不认识」，该词回到本环节
/// 重练时，题目完全没有标红（因为红色只画在英译汉的拼写卡片上）。
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

/// 红色提示色：与英译汉环节标红英文拼写用的是同一个常量
const Color _wrongHighlight = Color(0xFFE53935);

(WordVo, GetWordResult) _createTestData({List<SentenceVo>? sentences}) {
  final testWord = WordVo.c2('testword')
    ..id = 'w_test'
    ..setMeaningStr('n. 测试词');
  testWord.meaningItems = [
    MeaningItemVo('mi_1', 'n.', '测试词', null, null, sentences ?? []),
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

void main() {
  setUp(() {
    PlatformUtils.asrSupportedOverride = true;
    PlatformUtils.englishAsrSupportedOverride = true;
  });

  tearDown(() {
    PlatformUtils.asrSupportedOverride = null;
    PlatformUtils.englishAsrSupportedOverride = null;
  });

  testWidgets('汉译英题目：今天最近一次答错的词，中文释义标红', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    await tester.pumpWidget(_buildPage(const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.ch2En.json,
      isLatestAnswerWrongToday: true,
    )));
    await tester.pump();

    final meaning = tester.widget<Text>(find.text('测试词'));
    expect(meaning.style?.color, _wrongHighlight,
        reason: '刚答错的词，汉译英的题目（中文释义）必须和英译汉的拼写一样标红');
  });

  testWidgets('汉译英题目：不是刚答错的词，中文释义保持正常色', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData();

    await tester.pumpWidget(_buildPage(const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.ch2En.json,
      isLatestAnswerWrongToday: false,
    )));
    await tester.pump();

    final meaning = tester.widget<Text>(find.text('测试词'));
    expect(meaning.style?.color, isNot(_wrongHighlight),
        reason: '没有"刚答错"这回事的词，题目不该发红');
  });

  testWidgets('汉译英题目区：例句里的当前单词挖空成等长下划线', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData(sentences: [
      SentenceVo('s_1', 'They had to testword the whole plan.',
          '他们不得不放弃整个计划。', null, null, 'tts', 0, 0, UserVo.c2('u1')),
    ]);

    await tester.pumpWidget(_buildPage(const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.ch2En.json,
    )));
    await tester.pump();

    expect(find.text('They had to ________ the whole plan.'), findsOneWidget,
        reason: '汉译英题目区要给出挖空当前单词的例句做语境提示');
    expect(find.textContaining('testword'), findsNothing,
        reason: '答案拼写绝不能出现在题目区');
  });

  testWidgets('汉译英题目区：例句里没有当前单词时不显示例句', (tester) async {
    final (testWord, mockGetWordResult) = _createTestData(sentences: [
      SentenceVo('s_1', 'They gave up the whole plan.', '他们放弃了整个计划。',
          null, null, 'tts', 0, 0, UserVo.c2('u1')),
    ]);

    await tester.pumpWidget(_buildPage(const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockGetWordResult,
      studyStep: StudyStep.ch2En.json,
    )));
    await tester.pump();

    expect(find.byKey(const Key('ch2en_cloze_sentence')), findsNothing,
        reason: '挖不到当前单词就整行不显示，不能把完整例句端出来');
  });
}
