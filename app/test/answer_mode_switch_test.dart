import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/bdc/bdc.dart';
import 'package:nnbdc/page/bdc/providers/answer_mode.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
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

  /// 测试里模拟"换到下一个词"（真实流程由 handleWord 完成）
  BdcState get currentState => state;
  void pushState(BdcState next) => state = next;
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

/// 造一个已登录用户：StudyConfig 从它身上读（`preferKeyboardInSpelling` 决定输入框要不要抢焦点）
User _fakeUser({String? studyConfig}) {
  final DateTime now = AppClock.now();
  return User(
    id: 'test_user_id',
    userName: 'mock_user',
    password: '',
    nickName: 'Tester',
    email: '',
    gameScore: 0,
    dakaScore: 0,
    learnedDays: 0,
    learningFinished: false,
    inviteAwardTaken: false,
    isSuperAdmin: false,
    isAdmin: false,
    isInputor: false,
    cowDung: 0,
    throwDiceChance: 0,
    wordsPerDay: 5,
    dakaDayCount: 0,
    masteredWordsCount: 0,
    maxContinuousDakaDayCount: 0,
    continuousDakaDayCount: 0,
    todayStudyStarted: true,
    totalLearningSeconds: 0,
    todayLearningSeconds: 0,
    lastLearningDate: AppClock.today(),
    createTime: now,
    updateTime: now,
    studyConfig: studyConfig,
  );
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
    // 说档：题面是"说"，写面板与写档才有的「全屏」都不出现
    expect(find.text('说释义'), findsOneWidget);
    expect(find.byKey(const Key('bdc_typing_input')), findsNothing);
    expect(find.byKey(const Key('bdc_write_fullscreen_btn')), findsNothing);
  });

  testWidgets('写档默认就是卡片内手写，输入框不抢焦点，全屏图标在三段控件左边', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
            studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.speak));

    await tester.tap(find.byKey(const Key('bdc_answer_mode_write')));
    await tester.pumpAndSettle();

    // 顶栏说的是"写"而不是"说"
    expect(find.text('写释义'), findsOneWidget);
    expect(find.text('说释义'), findsNothing);
    // 答题卡里直接就是手写板（不是整页接管），键盘不自动弹
    expect(find.byType(HandwritingBoard), findsOneWidget);
    final TextField field =
        tester.widget<TextField>(find.byKey(const Key('bdc_typing_input')));
    expect(field.autofocus, false, reason: '写档默认手写，键盘由用户点输入框才弹');
    // 英译汉：紧凑操作栏里有「提交」（只带图标），顶栏有只带图标的「全屏」
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byKey(const Key('bdc_write_fullscreen_btn')), findsOneWidget);
    // 三段控件里没有「拼写练习」这种额外入口了
    expect(find.text('拼写'), findsNothing);

    // 默认不弹键盘；点一下输入框才切到键盘打字
    expect(tester.testTextInput.isVisible, false);
    await tester.tap(find.byKey(const Key('bdc_typing_input')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, true);
  });

  testWidgets('「全屏」把写档放大成之前的整页手写板', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
            studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.write));

    await tester.tap(find.byKey(const Key('bdc_write_fullscreen_btn')));
    await tester.pumpAndSettle();

    // 整页手写板的输入框提示（卡片内写档提示的是"点这里用键盘写释义"）
    expect(find.text('在此键入中文释义...'), findsOneWidget);
  });

  testWidgets('写档：汉译英是英文手写，没有提交，全屏图标仍在', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
            studyStep: StudyStep.ch2En.json, answerMode: AnswerMode.write));

    expect(find.text('拼单词'), findsOneWidget);
    expect(find.text('说发音'), findsNothing);
    expect(find.byKey(const Key('bdc_typing_input')), findsOneWidget);
    expect(find.byType(HandwritingBoard), findsOneWidget);
    // 英文停笔即自动识别判题，不需要「提交」
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byKey(const Key('bdc_write_fullscreen_btn')), findsOneWidget);
  });

  testWidgets('写档只是揭晓答案、没通过时，不补正确答案', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
                studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.write)
            .copyWith(hasFinishedAnswering: true, isScorePassed: false));

    expect(find.text('n. 苹果'), findsNothing);
    // 没通过时输入框还在，答案只在那条"揭晓"里给
    expect(find.byKey(const Key('bdc_typing_input')), findsOneWidget);
  });

  testWidgets('写档答对并通过时，输入框原地换成正确答案', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
                studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.write)
            .copyWith(hasFinishedAnswering: true, isScorePassed: true));

    // 复用输入行那一行的空间：输入框让位，答案顶上来（底下那行留给测评得分）
    expect(find.byKey(const Key('bdc_typing_input')), findsNothing);
    expect(find.text('n. 苹果'), findsOneWidget);
  });

  testWidgets('没用过提示时，写档不显示提示行', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
            studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.write));
    expect(find.textContaining('＿'), findsNothing);
  });

  testWidgets('键盘弹起触发版式切换时，输入框不丢焦点（键盘不闪一下就没）', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
            studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.write));

    // 点输入框 → 键盘起来
    await tester.tap(find.byKey(const Key('bdc_typing_input')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, true);

    // 系统回报"键盘已弹起"：版式从「画布 + 输入行」切到「只剩输入行」
    ProviderScope.containerOf(tester.element(find.byType(BdcPage)))
        .read(bdcNotifierProvider.notifier)
        .updateKeyboardVisibility(true);
    await tester.pumpAndSettle();

    expect(find.byType(HandwritingBoard), findsNothing);
    // 键盘占屏时测评面板收起，把高度让给输入行（键盘一收回来就恢复）
    expect(find.textContaining('下次复习'), findsNothing);
    expect(tester.testTextInput.isVisible, true,
        reason: '输入框若被重建就会丢焦点，表现就是键盘闪一下又缩回去');
  });

  testWidgets('上次用键盘答的：答对换到下一词后，键盘还能弹出来', (tester) async {
    Global.updateUserCache(
        _fakeUser(studyConfig: '{"preferKeyboardInSpelling":true}'));
    addTearDown(Global.clearUserCache);

    final (WordVo wordA, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(wordA, result,
            studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.write));
    final MockBdcNotifier notifier = ProviderScope.containerOf(
            tester.element(find.byType(BdcPage)))
        .read(bdcNotifierProvider.notifier) as MockBdcNotifier;
    expect(tester.testTextInput.isVisible, true, reason: '上次是键盘，进来就该弹');

    // 答对：这一行原地换成正确答案，输入框被卸载
    notifier.pushState(notifier.currentState
        .copyWith(hasFinishedAnswering: true, isScorePassed: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bdc_typing_input')), findsNothing);

    // 进入下一词
    final WordVo wordB = WordVo.c2('banana')..id = 'w_banana';
    wordB.meaningItems = [MeaningItemVo('mi_2', 'n.', '香蕉', null, null, [])];
    notifier.pushState(notifier.currentState.copyWith(
      word: wordB,
      wordWrapper: WordWrapper(wordB, null),
      hasFinishedAnswering: false,
      isScorePassed: false,
    ));
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, true,
        reason: '上一词是用键盘答的，下一词要能接着打');
  });

  testWidgets('上次用手写的：答对换到下一词后，键盘不会自己弹', (tester) async {
    Global.updateUserCache(
        _fakeUser(studyConfig: '{"preferKeyboardInSpelling":false}'));
    addTearDown(Global.clearUserCache);

    final (WordVo wordA, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(wordA, result,
            studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.write));
    final MockBdcNotifier notifier = ProviderScope.containerOf(
            tester.element(find.byType(BdcPage)))
        .read(bdcNotifierProvider.notifier) as MockBdcNotifier;
    expect(tester.testTextInput.isVisible, false);

    notifier.pushState(notifier.currentState
        .copyWith(hasFinishedAnswering: true, isScorePassed: true));
    await tester.pumpAndSettle();

    final WordVo wordB = WordVo.c2('banana')..id = 'w_banana';
    wordB.meaningItems = [MeaningItemVo('mi_2', 'n.', '香蕉', null, null, [])];
    notifier.pushState(notifier.currentState.copyWith(
      word: wordB,
      wordWrapper: WordWrapper(wordB, null),
      hasFinishedAnswering: false,
      isScorePassed: false,
    ));
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, false,
        reason: '手写模式下不该抢焦点弹键盘');
  });

  testWidgets('键盘占屏、卡片被压扁时，写面板不撑爆卡片', (tester) async {
    // 复现线上几何：视口不算小，但键盘吃掉了大半，答题卡可用高度掉到比输入行还矮
    tester.view.physicalSize = const Size(1200, 500);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.reset);

    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
                studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.write)
            .copyWith(isKeyboardVisible: true));

    // 输入行所在槽会缩到可用高度并在行内滚动，不再溢出
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('bdc_typing_input')), findsOneWidget);
  });

  testWidgets('键盘弹起时画布让位，只留输入行（不再撑爆卡片）', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
                studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.write)
            .copyWith(isKeyboardVisible: true));

    // 画布让位（它本来也看不见），输入框还在，且没有溢出异常
    expect(find.byType(HandwritingBoard), findsNothing);
    expect(find.byKey(const Key('bdc_typing_input')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('写档的「提示」：点一次露一个汉字，其余仍是＿', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    final WordWrapper hinted = WordWrapper(testWord, null)..hintLetterCount = 1;
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
                studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.write)
            .copyWith(wordWrapper: hinted, hintTapCount: 1));

    expect(find.text('n. 苹＿'), findsOneWidget);
    // 紧凑操作栏里有「提示」（只带图标）
    expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
  });

  testWidgets('答案行只把写对的释义项标绿，项之间用常用度圆点分隔', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    testWord.meaningItems = [
      MeaningItemVo('mi_1', 'n.', '苹果', null, null, []),
      MeaningItemVo('mi_2', 'v.', '考验', null, null, []),
    ];
    final wrapper = WordWrapper(testWord, null);
    // 只答对了第一个释义项
    wrapper.asrMatchedMeaningItemParts.add(Pair(0, 0));

    await _pumpPage(
        tester,
        const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      wordWrapper: wrapper,
      currentGetWordResult: result,
      studyStep: StudyStep.en2Ch.json,
      answerMode: AnswerMode.write,
      hasFinishedAnswering: true,
      isScorePassed: true,
    ));

    const Color green = Color(0xFF10B981);
    final Text first = tester.widget<Text>(find.text('n. 苹果'));
    final Text second = tester.widget<Text>(find.text('v. 考验'));
    expect(first.style?.color, green, reason: '写对的释义项要绿色');
    expect(second.style?.color, isNot(green),
        reason: '没写到的释义项用默认字色，不能也跟着绿');
    // 分隔符改成了常用度圆点：不再出现分号
    expect(find.text('；'), findsNothing);
  });

  testWidgets('写档答对时，汉译英给的正确答案是这个词的拼写', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
                studyStep: StudyStep.ch2En.json, answerMode: AnswerMode.write)
            .copyWith(hasFinishedAnswering: true, isScorePassed: true));
    expect(find.text('apple'), findsWidgets);
  });

  testWidgets('英译汉：题目区单词旁的铅笔直接进全屏拼写练习', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
            studyStep: StudyStep.en2Ch.json, answerMode: AnswerMode.speak));

    // 说/选/写三档都能看到它（它只练这个词怎么拼，不改变当前作答方式）
    expect(find.byKey(const Key('bdc_word_spelling_practice_btn')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('bdc_word_spelling_practice_btn')));
    await tester.pumpAndSettle();

    // 打开的是全屏英文拼写板（不是中文默写）
    expect(find.text('请拼写单词：'), findsOneWidget);
    expect(find.text('在此键入单词...'), findsOneWidget);
  });

  testWidgets('汉译英：题目区没有拼写练习的铅笔', (tester) async {
    final (WordVo testWord, GetWordResult result) = _createTestData();
    await _pumpPage(
        tester,
        _stateWith(testWord, result,
            studyStep: StudyStep.ch2En.json, answerMode: AnswerMode.choose));

    expect(find.byKey(const Key('bdc_word_spelling_practice_btn')),
        findsNothing);
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
