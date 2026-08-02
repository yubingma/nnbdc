import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nnbdc/services/study_cache_manager.dart';

// 手写 MockAsr，捕获并拦截所有的原生方法
class MockAsr implements Asr {
  final AsrState _state = AsrState.initialized;
  final List<Function(AsrState)> _stateListeners = [];

  int startAsrCallCount = 0;
  int stopAsrCallCount = 0;

  @override
  AsrState get state => _state;

  @override
  bool get isPreloaded => true;

  @override
  bool get permissionGranted => true;

  @override
  set permissionGranted(bool value) {}

  @override
  AsrLanguage? get currentLanguage => null;

  @override
  Future<void> updateLanguage(AsrLanguage language) async {}

  @override
  void addStateListener(Function(AsrState) listener) {
    _stateListeners.add(listener);
  }

  @override
  void removeStateListener(Function(AsrState) listener) {
    _stateListeners.remove(listener);
  }

  @override
  Future<void> initAsr(void Function(dynamic)? asrListener) async {}

  @override
  Future<void> preloadModels() async {}

  @override
  Future<void> startAsr(AsrLanguage language, {List<String>? phrases, bool playHintSound = true}) async {
    startAsrCallCount++;
  }

  @override
  Future<String?> stopAsr() async {
    stopAsrCallCount++;
    return null;
  }

  @override
  Future<void> startMicrophone() async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> reset() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// 手写 MockAudioPlayer，捕获并拦截原生语音的方法
class MockAudioPlayer implements ja.AudioPlayer {
  @override
  bool get playing => false;

  @override
  ja.ProcessingState get processingState => ja.ProcessingState.idle;

  @override
  Stream<ja.PlayerState> get playerStateStream => Stream.value(ja.PlayerState(false, ja.ProcessingState.idle));

  @override
  Duration? get duration => null;

  @override
  Duration get position => Duration.zero;

  @override
  Stream<Duration> get positionStream => Stream.value(Duration.zero);

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration? position, {int? index}) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBuildContext implements BuildContext {
  @override
  bool get mounted => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // 确保 Flutter 绑定初始化（针对测试环境下的 MethodChannel 等服务模拟）
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  final now = AppClock.now();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async {
        return [];
      },
    );
    // 拦截 just_audio 平台的底层 MethodChannel，返回成功数据
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        return {};
      },
    );
    // 拦截 audio_session 平台的底层 MethodChannel，返回成功数据
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  setUp(() async {
    StudyAudioSessionController.instance.audioSessionConfigured = true;
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);

    testUser = User(
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
      studyConfig: '{"autoPlayWord":false,"autoPlaySentence":false}',
    );
    await db.usersDao.saveUser(testUser, false);

    Global.currentUserId = 'test_user_id';
    Global.updateUserCache(testUser);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Prefs.write('currentUserId', 'test_user_id');

    // 插入学习步骤配置: 1个答题环节(En2Ch)
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'En2Ch',
          seq: 0,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));

    // 生成 Mock 词书和映射
    var dictId = 'mock_dict_1';
    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '测试词书',
          wordCount: 10,
          isShared: false,
          isReady: true,
          ownerId: 'sys',
          visible: true,
          editable: false,
          deletable: false,
          createTime: now,
          updateTime: now,
        ));

    await db.into(db.learningDicts).insert(LearningDict(
          userId: testUser.id,
          dictId: dictId,
          isPrivileged: false,
          fetchMastered: false,
          sortAlg: 'ORIGINAL',
          createTime: now,
          updateTime: now,
        ));

    // 插入 1 个单词供学习
    var wordId = 'word_1';
    await db.into(db.words).insert(Word(
          id: wordId,
          spell: 'apple',
          popularity: 100,
          createTime: now,
          updateTime: now,
        ));

    await db.into(db.meaningItems).insert(MeaningItem(
          id: 'mim_1',
          wordId: wordId,
          dictId: Global.commonDictId,
          ciXing: 'n.',
          meaning: '苹果',
          popularity: 100,
          ownerId: Global.sysUserId,
          createTime: now,
          updateTime: now,
        ));

    await db.into(db.dictWords).insert(DictWord(
          dictId: dictId,
          wordId: wordId,
          seq: 1,
          unit: 0,
          createTime: now,
          updateTime: now,
        ));

    await db.into(db.learningWords).insert(LearningWord(
          userId: testUser.id,
          wordId: wordId,
          addTime: now,
          addDay: 1,
          batchId: 1,
          lastLearningDate: AppClock.today(),
          stability: 0.0,
          isTodayNewWord: true,
          learnedTimes: 0,
          todayLearnedTimes: 0,
          learningOrder: 1,
          createTime: now,
          updateTime: now,
        ));
  });

  tearDown(() async {
    await db.close();
  });

  test('BdcNotifier - loadData 和提示词状态变更单元测试', () async {
    final mockAsr = MockAsr();

    final container = ProviderContainer(
      overrides: [
        asrProvider.overrideWithValue(mockAsr),
      ],
    );
    addTearDown(container.dispose);

    // 1. 初始状态：dataLoaded 应为 false，单词应为 null
    var state = container.read(bdcNotifierProvider);
    expect(state.dataLoaded, false);
    expect(state.word, null);

    // 2. 调用 loadData 加载数据
    final notifier = container.read(bdcNotifierProvider.notifier);
    final context = FakeBuildContext();
    await notifier.loadData(context);

    // 验证数据正确加载
    state = container.read(bdcNotifierProvider);
    expect(state.dataLoaded, true);
    expect(state.word != null, true);
    expect(state.word!.spell, 'apple');
    expect(state.studyStep, 'En2Ch');

    // 3. 验证提示词逻辑 (giveALittleHint)
    expect(state.hintTapCount, 0);
    notifier.giveALittleHint();

    state = container.read(bdcNotifierProvider);
    expect(state.hintTapCount, 1);
    expect(state.wordWrapper!.hintLetterCount, 1);

    // 4. 验证手写板状态翻转 (toggleHandwritingBoard)
    expect(state.showHandwritingBoard, false);
    notifier.toggleHandwritingBoard();

    state = container.read(bdcNotifierProvider);
    expect(state.showHandwritingBoard, true);

    // 5. 单词环节 (En2Ch) PTT 不生效：startPttAsr 直接返回，不启动识别
    expect(state.studyStep, 'En2Ch');
    notifier.startPttAsr();
    await Future.delayed(const Duration(milliseconds: 50));
    expect(mockAsr.startAsrCallCount, 0);
    expect(container.read(bdcNotifierProvider).isPttPressed, false);

    // 等待所有后台异步任务（例如 StudyBo 里的单词拼写预获取）在数据库关闭前执行完毕，防止出现 Can't re-open database 警告
    await Future.delayed(const Duration(milliseconds: 100));
  });

  test('BdcNotifier - isWordMastered 在切换下一个词时应重置为 false', () async {
    // 清除 StudyCacheManager 单例缓存，防止上一条测试的缓存干扰该测试
    StudyCacheManager().clear();

    // 1. 在数据库中为 test_user 插入已掌握词书
    var masteredDictId = 'mock_mastered_dict';
    await db.into(db.dicts).insert(Dict(
          id: masteredDictId,
          name: '已掌握',
          wordCount: 0,
          isShared: false,
          isReady: true,
          ownerId: testUser.id,
          visible: true,
          editable: false,
          deletable: false,
          createTime: now,
          updateTime: now,
        ));

    // 2. 在数据库中为 test_user 插入第 2 个单词以供切换
    var wordId2 = 'word_2';
    await db.into(db.words).insert(Word(
          id: wordId2,
          spell: 'banana',
          popularity: 90,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.meaningItems).insert(MeaningItem(
          id: 'mim_2',
          wordId: wordId2,
          dictId: Global.commonDictId,
          ciXing: 'n.',
          meaning: '香蕉',
          popularity: 90,
          ownerId: Global.sysUserId,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.dictWords).insert(DictWord(
          dictId: 'mock_dict_1',
          wordId: wordId2,
          seq: 2,
          unit: 0,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.learningWords).insert(LearningWord(
          userId: testUser.id,
          wordId: wordId2,
          addTime: now,
          addDay: 1,
          batchId: 1,
          lastLearningDate: AppClock.today(),
          stability: 0.0,
          isTodayNewWord: true,
          learnedTimes: 0,
          todayLearnedTimes: 0,
          learningOrder: 2,
          createTime: now,
          updateTime: now,
        ));

    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [
        asrProvider.overrideWithValue(mockAsr),
      ],
    );
    final keepAlive = container.listen(bdcNotifierProvider, (_, __) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });

    final notifier = container.read(bdcNotifierProvider.notifier);
    final context = FakeBuildContext();
    await notifier.loadData(context);

    var state = container.read(bdcNotifierProvider);
    expect(state.word!.spell, 'apple');
    expect(state.isWordMastered, false);

    // 3. 将当前词 'apple' 的掌握状态设为 true
    notifier.updateIsWordMastered(true);
    state = container.read(bdcNotifierProvider);
    expect(state.isWordMastered, true);

    // 3. 切换到下一个词
    final success = await notifier.getNextWord(true);
    state = container.read(bdcNotifierProvider);
    
    expect(success, true);

    // 4. 验证新载入的词 'banana'，其 isWordMastered 已经重置为 false
    expect(state.word!.spell, 'banana');
    expect(state.isWordMastered, false); // 核心保护性断言

    await Future.delayed(const Duration(milliseconds: 100));
  });

  test('BdcNotifier - 英中模式说出半数/全部意思，部分说对播放正确提示音但未通过', () async {
    // 1. 插入一个拥有多个释义子项的单词
    final now = AppClock.now();
    var wordId = 'word_test_meanings';
    await db.into(db.words).insert(Word(
          id: wordId,
          spell: 'banana_test',
          popularity: 100,
          createTime: now,
          updateTime: now,
        ));

    await db.into(db.meaningItems).insert(MeaningItem(
          id: 'mim_test_meanings',
          wordId: wordId,
          dictId: Global.commonDictId,
          ciXing: 'n.',
          meaning: '香蕉;芭蕉;甘蕉',
          popularity: 100,
          ownerId: Global.sysUserId,
          createTime: now,
          updateTime: now,
        ));

    await db.into(db.dictWords).insert(DictWord(
          dictId: 'mock_dict_1',
          wordId: wordId,
          seq: 5,
          unit: 0,
          createTime: now,
          updateTime: now,
        ));

    await db.into(db.learningWords).insert(LearningWord(
          userId: testUser.id,
          wordId: wordId,
          addTime: now,
          addDay: 1,
          batchId: 1,
          lastLearningDate: AppClock.today(),
          stability: 0.0,
          isTodayNewWord: true,
          learnedTimes: 0,
          todayLearnedTimes: 0,
          learningOrder: 5,
          createTime: now,
          updateTime: now,
        ));

    // Clear StudyCacheManager cache so it fetches the new list
    StudyCacheManager().clear();

    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [
        asrProvider.overrideWithValue(mockAsr),
      ],
    );
    final keepAlive = container.listen(bdcNotifierProvider, (_, __) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });

    final notifier = container.read(bdcNotifierProvider.notifier);
    final context = FakeBuildContext();
    await notifier.loadData(context);

    // 切换到刚才插入的这个词 (banana_test)
    var state = container.read(bdcNotifierProvider);
    while (state.word?.spell != 'banana_test') {
      await notifier.getNextWord(true);
      state = container.read(bdcNotifierProvider);
    }

    expect(state.word!.spell, 'banana_test');
    expect(state.studyStep, 'En2Ch');

    // 2. 设置通过条件为 ALL 或者是 HALF
    notifier.updateAsrPassRuleCache('ALL');
    state = container.read(bdcNotifierProvider);
    expect(state.asrPassRuleCache, 'ALL');

    // 3. 用户只说对一个释义：“香蕉”
    await notifier.onAsrResult(jsonEncode({
      'best': '香蕉',
      'candidates': ['香蕉'],
    }));
    
    state = container.read(bdcNotifierProvider);
    // 应该没有答完，因为需要全部答对（3个）
    expect(state.hasFinishedAnswering, false);
    // 但是 matchedCount 增加到了 1
    expect(state.wordWrapper!.asrMatchedMeaningItemParts.length, 1);

    // 4. 用户又说对一个新释义：“芭蕉”
    await notifier.onAsrResult(jsonEncode({
      'best': '芭蕉',
      'candidates': ['芭蕉'],
    }));
    
    state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, false);
    expect(state.wordWrapper!.asrMatchedMeaningItemParts.length, 2);

    // 5. 用户说对最后一个释义：“甘蕉”
    await notifier.onAsrResult(jsonEncode({
      'best': '甘蕉',
      'candidates': ['甘蕉'],
    }));
    
    state = container.read(bdcNotifierProvider);
    // 现在全部答对，应该通过
    expect(state.hasFinishedAnswering, true);
    expect(state.wordWrapper!.asrMatchedMeaningItemParts.length, 3);
  });

  test('测试例句模式下的语音识别与LCS相似度模糊匹配判定', () async {
    final container = ProviderContainer(
      overrides: [
        asrProvider.overrideWithValue(MockAsr()),
      ],
    );
    final keepAlive = container.listen(bdcNotifierProvider, (_, __) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });

    final notifier = container.read(bdcNotifierProvider.notifier);
    
    // 1. 验证中文句子匹配（EnSentence2Ch 60% 字符级阈值）
    // 目标：“我每天早上吃一个苹果。” (10个中文字)
    // 匹对“吃一个苹果”，LCS为 5, 5/10 = 50%
    expect(notifier.getChineseSentenceMatchScore('吃一个苹果', '我每天早上吃一个苹果。'), 50);
    // 匹对“我每天吃苹果”，LCS为 6, 6/10 = 60%
    expect(notifier.getChineseSentenceMatchScore('我每天吃苹果', '我每天早上吃一个苹果。'), 60);
    // 匹对“我每天早上都吃苹果”，LCS为 8, 8/10 = 80%
    expect(notifier.getChineseSentenceMatchScore('我每天早上都吃苹果', '我每天早上吃一个苹果。'), 80);

    // 2. 验证英文句子匹配（ChSentence2En 70% 单词级偏置阈值）
    // 目标：“I eat an apple every morning.” (6个英文单词)
    // 匹对“I eat apple”，分词为 [i, eat, apple]，LCS为 3, 3/6 = 50%
    expect(await notifier.getEnglishSentenceMatchScore('I eat apple', 'I eat an apple every morning.'), 50);
    // 匹对“I eat an apple morning”，分词为 [i, eat, an, apple, morning]，LCS为 5, 5/6 = 83%
    expect(await notifier.getEnglishSentenceMatchScore('I eat an apple morning', 'I eat an apple every morning.'), 83);
    // 匹对“I eat an apple every morning”，LCS单词为 6, 6/6 = 100%
    expect(await notifier.getEnglishSentenceMatchScore('I eat an apple every morning.', 'I eat an apple every morning.'), 100);

    // 3. 验证智能重叠拼接去重算法 (stitchTexts)
    // 中文无重合拼接
    expect(BdcNotifier.stitchTexts('我每天', '一个苹果', isEnglish: false), '我每天一个苹果');
    // 中文有重合拼接
    expect(BdcNotifier.stitchTexts('我每天', '每天吃苹果', isEnglish: false), '我每天吃苹果');
    expect(BdcNotifier.stitchTexts('我每天早上吃', '吃一个苹果', isEnglish: false), '我每天早上吃一个苹果');
    
    // 英文无重合拼接
    expect(BdcNotifier.stitchTexts('i eat', 'a watermelon', isEnglish: true), 'i eat a watermelon');
    // 英文有重合拼接 (包括单词级大小写归一化匹配)
    expect(BdcNotifier.stitchTexts('i eat', 'eat an apple', isEnglish: true), 'i eat an apple');
    expect(BdcNotifier.stitchTexts('I have', 'have a Apple', isEnglish: true), 'I have a Apple');
  });

  test('例句环节 PTT 按下说话:按下启动识别、松开停止并判定、空文本静默放弃', () async {
    // 1. 追加例句步骤(EnSentence2Ch, seq 1),使 activeUserStudySteps = [En2Ch, EnSentence2Ch]
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'EnSentence2Ch',
          seq: 1,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    // 将 word_1 的今日学习次数置为 1,使 StudyBo 计算 stepIndex = todayLearnedTimes = 1(例句步骤)
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(todayLearnedTimes: const Value(1)));
    // 为 word_1 的释义项 mim_1 插入例句数据
    await db.into(db.sentences).insert(Sentence(
          id: 'snt_1',
          english: 'I eat an apple every morning.',
          chinese: '我每天早上吃一个苹果。',
          englishDigest: 'I eat an apple every morning.',
          partOfSpeech: '',
          theType: 'tts',
          handCount: 0,
          footCount: 0,
          authorId: 'sys',
          ownerId: 'sys',
          meaningItemId: 'mim_1',
          wordMeaning: '苹果',
          createTime: now,
          updateTime: now,
        ));
    StudyCacheManager().clear();

    final mockAsr = MockAsr();
    // 将 Mock 注入 StudyAudioSessionController 内部,使 startSession → _asr.startAsr 走 Mock
    StudyAudioSessionController.instance.debugSetAsrForTesting(mockAsr);
    // 测试环境运行在 macOS 上,需模拟 ASR 支持,使 transitTo(record) 不降级为 playback
    PlatformUtils.asrSupportedOverride = true;
    addTearDown(() => PlatformUtils.asrSupportedOverride = null);
    final container = ProviderContainer(
      overrides: [
        asrProvider.overrideWithValue(mockAsr),
      ],
    );
    final keepAlive = container.listen(bdcNotifierProvider, (_, __) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });

    final notifier = container.read(bdcNotifierProvider.notifier);
    final context = FakeBuildContext();
    await notifier.loadData(context);

    // 2. 应直接进入例句步骤(stepIndex=1)
    var state = container.read(bdcNotifierProvider);
    expect(state.studyStep, 'EnSentence2Ch');
    expect(state.word?.spell, 'apple');

    // 3. 进入例句环节后不应自动开麦
    expect(mockAsr.startAsrCallCount, 0);

    // 4. 按下 PTT → 启动识别,isPttPressed 置为 true
    notifier.startPttAsr();
    // startSession 走真实 controller 串行队列 + transitTo 有 60-100ms 延时,轮询等待 ASR 真正启动
    for (var i = 0; i < 20 && mockAsr.startAsrCallCount < 1; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    state = container.read(bdcNotifierProvider);
    expect(state.isPttPressed, true);
    expect(mockAsr.startAsrCallCount, 1);
    // loadData → getNextWord 末尾会做一次 ASR 清理,记录为基线
    final stopAsrBaseline = mockAsr.stopAsrCallCount;

    // 5. 松开 PTT 但没说话 → 不判定,静默放弃
    await notifier.stopPttAsr();
    await Future.delayed(const Duration(milliseconds: 50));
    state = container.read(bdcNotifierProvider);
    expect(state.isPttPressed, false);
    expect(state.hasFinishedAnswering, false);
    expect(mockAsr.stopAsrCallCount, stopAsrBaseline + 1);

    // 5.1 遗留事件隔离：松开后原生端 stop 前已排队的最终结果到达，
    //     应被忽略(例句环节 _isPttPressed=false 守卫)，不污染文本也不触发判定
    await notifier.onAsrResult(jsonEncode({
      'best': '我每天早上吃一个苹果',
      'candidates': ['我每天早上吃一个苹果'],
      'isFinal': true,
    }));
    state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, false, reason: '松开后的遗留事件不得触发判定');
    expect(state.currentAsrCandidates, isEmpty, reason: '松开后的遗留事件不得污染识别候选');

    // 6. 再次按下 PTT 并说出正确中文翻译 → 松开即判定通过
    notifier.startPttAsr();
    for (var i = 0; i < 20 && mockAsr.startAsrCallCount < 2; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect(mockAsr.startAsrCallCount, 2);
    // 新一轮识别从干净状态开始：遗留事件未污染累积文本
    state = container.read(bdcNotifierProvider);
    expect(state.currentAsrCandidates, isEmpty, reason: '新一轮按住应从空候选开始');

    await notifier.onAsrResult(jsonEncode({
      'best': '我每天早上吃一个苹果',
      'candidates': ['我每天早上吃一个苹果'],
      'isFinal': true,
    }));
    await notifier.stopPttAsr();
    await Future.delayed(const Duration(milliseconds: 100));

    state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, true);

    // 7. 答完后 PTT 不再生效：hasFinishedAnswering=true 时按下直接返回，不启动识别
    final callsBeforeAnsweredRetry = mockAsr.startAsrCallCount;
    notifier.startPttAsr();
    await Future.delayed(const Duration(milliseconds: 50));
    expect(mockAsr.startAsrCallCount, callsBeforeAnsweredRetry);
    expect(container.read(bdcNotifierProvider).isPttPressed, false);

    await Future.delayed(const Duration(milliseconds: 100));
  });

  test('例句环节 PTT 补充模式:光标处插入新识别内容,锚点前后文本保留', () async {
    // 复用例句步骤 setup
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'EnSentence2Ch',
          seq: 1,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(todayLearnedTimes: const Value(1)));
    await db.into(db.sentences).insert(Sentence(
          id: 'snt_2',
          english: 'I eat an apple every morning.',
          chinese: '我每天早上吃一个苹果。',
          englishDigest: 'I eat an apple every morning.',
          partOfSpeech: '',
          theType: 'tts',
          handCount: 0,
          footCount: 0,
          authorId: 'sys',
          ownerId: 'sys',
          meaningItemId: 'mim_1',
          wordMeaning: '苹果',
          createTime: now,
          updateTime: now,
        ));
    StudyCacheManager().clear();

    final mockAsr = MockAsr();
    StudyAudioSessionController.instance.debugSetAsrForTesting(mockAsr);
    PlatformUtils.asrSupportedOverride = true;
    addTearDown(() => PlatformUtils.asrSupportedOverride = null);
    final container = ProviderContainer(
      overrides: [
        asrProvider.overrideWithValue(mockAsr),
      ],
    );
    final keepAlive = container.listen(bdcNotifierProvider, (_, __) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });

    final notifier = container.read(bdcNotifierProvider.notifier);
    final context = FakeBuildContext();
    await notifier.loadData(context);
    expect(container.read(bdcNotifierProvider).studyStep, 'EnSentence2Ch');

    // 1. 首次按住:识别出一部分(如"我每天早上"),松开
    notifier.startPttAsr();
    for (var i = 0; i < 20 && mockAsr.startAsrCallCount < 1; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    await notifier.onAsrResult(jsonEncode({
      'best': '我每天早上',
      'candidates': ['我每天早上'],
      'isFinal': false,
    }));
    // 识别增量写入答案区
    expect(notifier.sentenceAnswerController.text, '我每天早上');
    await notifier.stopPttAsr();
    await Future.delayed(const Duration(milliseconds: 50));
    expect(container.read(bdcNotifierProvider).isPttPressed, false);
    // 未答完(文本不完整,判定不通过)
    expect(container.read(bdcNotifierProvider).hasFinishedAnswering, false);

    // 2. 光标移到文本中间(如"我每天|早上"),再次按住补充
    notifier.sentenceAnswerController.selection =
        const TextSelection.collapsed(offset: 3); // 光标在"早上"前
    notifier.startPttAsr();
    for (var i = 0; i < 20 && mockAsr.startAsrCallCount < 2; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    // 补充识别"都吃",应插入光标处:我每天[都吃]早上
    await notifier.onAsrResult(jsonEncode({
      'best': '都吃',
      'candidates': ['都吃'],
      'isFinal': false,
    }));
    expect(notifier.sentenceAnswerController.text, '我每天' + '都吃' + '早上',
        reason: '补充内容应插入光标处,锚点前后文本保留');
    await notifier.stopPttAsr();
    await Future.delayed(const Duration(milliseconds: 50));
    expect(container.read(bdcNotifierProvider).isPttPressed, false);

    await Future.delayed(const Duration(milliseconds: 100));
  });
}
