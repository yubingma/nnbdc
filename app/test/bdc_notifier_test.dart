import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/db/learning_word_extensions.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/util/ai_referee_util.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/fsrs.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/study_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';

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

/// 等待 notifier 内部异步刷新的「本组进度」落定（handleWord 中以 unawaited 调用）
Future<void> _waitUntil(
  ProviderContainer container,
  bool Function(BdcState state) predicate,
) async {
  for (int i = 0; i < 100; i++) {
    if (predicate(container.read(bdcNotifierProvider))) return;
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

/// 执行 [action]，只放行"测试环境没有 ToastificationWrapper"导致的提示条断言错误。
///
/// 取词失败分支会弹提示条（ErrorHandler.handleError → ToastUtil.error），
/// 而纯单元测试没有 Toastification 覆盖层，弹提示条必然抛断言错误。
/// 该断言不影响失败分支对"已受理凭据 / 受理资格"的处理，故这里显式接住它；
/// 其它任何异常照旧抛出，不得被吞掉。
Future<void> _ignoreToastUnavailable(Future<void> Function() action) async {
  try {
    await action();
  } on AssertionError catch (e) {
    if (!'$e'.contains('Toastification is not initialized')) rethrow;
  }
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
    ThrottledDbSyncService().reset();
    StudyCacheManager().clear();
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

    // 插入学习步骤配置（三组）: 测评 En2Ch，答对/答错组默认空
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          scope: 'new',
          group: 'check',
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
        isExtra: false,
        ));
  });

  tearDown(() async {
    ThrottledDbSyncService().reset();
    StudyCacheManager().clear();
    await Future.delayed(const Duration(milliseconds: 50));
    try {
      await db.close();
    } catch (_) {}
    MyDatabase.setInstanceForTesting(null);
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

  test('BdcNotifier - 新手引导展示期间挂起语音识别，收起后恢复', () async {
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
    await notifier.loadData(FakeBuildContext());
    expect(container.read(bdcNotifierProvider).studyStep, 'En2Ch');

    // 单词环节默认开麦：等到识别真正启动
    for (var i = 0; i < 20 && mockAsr.startAsrCallCount < 1; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    final startBaseline = mockAsr.startAsrCallCount;
    expect(startBaseline, greaterThanOrEqualTo(1));

    // 引导弹出：识别立刻停掉
    final stopBaseline = mockAsr.stopAsrCallCount;
    notifier.setGuideShowing(true);
    for (var i = 0; i < 20 && mockAsr.stopAsrCallCount < stopBaseline + 1; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect(mockAsr.stopAsrCallCount, stopBaseline + 1,
        reason: '引导弹出时应先停掉识别');

    // 引导期间任何硬件意图同步都不得再开麦：用户此时说话不该被判分
    notifier.handleTabChangeForAsr();
    await Future.delayed(const Duration(milliseconds: 150));
    expect(mockAsr.startAsrCallCount, startBaseline,
        reason: '引导展示期间不得开麦');

    // 引导期间到达的遗留识别结果同样不得进入判定
    await notifier.onAsrResult(jsonEncode({
      'best': '苹果',
      'candidates': ['苹果'],
      'isFinal': true,
    }));
    await Future.delayed(const Duration(milliseconds: 150));
    expect(container.read(bdcNotifierProvider).hasFinishedAnswering, false,
        reason: '引导展示期间的识别结果不得判分');

    // 收起引导：按当前环节恢复开麦
    notifier.setGuideShowing(false);
    for (var i = 0; i < 20 && mockAsr.startAsrCallCount <= startBaseline; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect(mockAsr.startAsrCallCount, greaterThan(startBaseline),
        reason: '收起引导后应恢复识别');

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
        isExtra: false,
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

  test('BdcNotifier - 答错的词不缓存答题态：重练时不得直接显示上一轮的答案', () async {
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
    await notifier.loadData(FakeBuildContext());

    final answeredWordId = container.read(bdcNotifierProvider).word!.id!;

    // 测评答错（等价于选错、看完详情页后点「下一词」）
    // 先受理这次作答（与线上判题链路一致），再提交流转
    notifier.acceptAnswerForTesting(FsrsRating.again);
    await notifier.getNextWord(true, fsrsRating: FsrsRating.again);
    final state = container.read(bdcNotifierProvider);

    expect(state.wordUIStates.containsKey(answeredWordId), false,
        reason: '答错的词会留在本环节重练，不得留下"已答完"的 UI 状态缓存，'
            '否则重练时 _restoreWordState 会把上一轮揭晓的答案原样恢复出来');
    expect(state.hasFinishedAnswering, false,
        reason: '重练应重新开始作答，而不是显示上一轮揭晓的答案');
    expect(state.selectedAnswerIndex, null);
  });

  test('BdcNotifier - 测评答错重练时仍提供测评结果参考（不因 stepIndex 仍为 0 而丢失）', () async {
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
    await notifier.loadData(FakeBuildContext());

    // 测评首次作答前：今天还没测过，无参考值
    expect(container.read(bdcNotifierProvider).assessmentRating, isNull);

    // 测评答错 → 留在测评环节循环重练
    // 先受理这次作答（与线上判题链路一致），再提交流转
    notifier.acceptAnswerForTesting(FsrsRating.again);
    await notifier.getNextWord(true, fsrsRating: FsrsRating.again);
    final state = container.read(bdcNotifierProvider);

    expect(state.currentGetWordResult!.stepIndex, 0, reason: '仍在测评环节重练');
    expect(state.assessmentRating, FsrsRating.again,
        reason: '该词今天已经测过一次（首答答错），重练时应当能看到测评结果');
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
        isExtra: false,
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
    // 已命中部分释义即可离开，但答案尚未揭晓：底部「下一词」流转按钮此时不渲染，
    // 只能由「不认识/再学学」进入单词详情页看答案，杜绝未看答案就跳到下一词
    expect(state.canLeaveCurrWord, true, reason: '已命中部分释义允许离开当前词');
    expect(notifier.hasSeenAnswer, false, reason: '未达通过线时答案未揭晓，不渲染「下一词」按钮');

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
    expect(notifier.hasSeenAnswer, true, reason: '答案已揭晓，此时才渲染「下一词」按钮');
  });

  test('BdcNotifier - 英中模式已说中的释义重复识别时不应触发 AI 裁判（不得整词放行绕过半数门槛）', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    // 3 个释义子项 + 通过线为"答对一半"（需答对 2 个）
    container.read(bdcNotifierProvider).wordWrapper!.word.meaningItems = [
      MeaningItemVo.from('a.', '竞争的;竞争激烈的;好胜的'),
    ];
    notifier.updateAsrPassRuleCache('HALF');

    // 用户说"竞争性的"（命中"竞争的"，变绿），只答对 1/2，未通过
    await notifier.onAsrResult(jsonEncode({
      'best': '竞争性的',
      'candidates': ['竞争性的'],
      'isFinal': false,
    }));
    var state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, false, reason: '只答对 1/2，不应通过');
    expect(state.wordWrapper!.asrMatchedMeaningItemParts.length, 1);
    expect(notifier.hasPendingWordAiReferee, false, reason: '本地命中后不应有待触发的 AI 裁判');

    // 同一答案的收尾识别帧（重复文本）：本次没有"新增"命中，但本地已命中过释义，
    // 绝不能因此把回答交给 AI 裁判——AI 认可会把全部释义标记为已答对并整词放行。
    await notifier.onAsrResult(jsonEncode({
      'best': '竞争性的',
      'candidates': ['竞争性的'],
      'isFinal': true,
    }));
    state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, false, reason: '仍只答对 1/2，不应通过');
    expect(notifier.hasPendingWordAiReferee, false,
        reason: '本地已命中释义时，AI 裁判不应被调度（否则整词放行会绕过半数门槛）');

    // 继续说中第二个释义才应通过
    await notifier.onAsrResult(jsonEncode({
      'best': '好胜的',
      'candidates': ['好胜的'],
      'isFinal': true,
    }));
    state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, true, reason: '答对 2/3 达到半数门槛，应通过');
  });

  test('BdcNotifier - 通过条件已满足时重复说出已命中释义也应判通过（不依赖本次新增命中）', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    // 3 个释义子项 + 通过线为"答对一半"（需答对 2 个）
    container.read(bdcNotifierProvider).wordWrapper!.word.meaningItems = [
      MeaningItemVo.from('a.', '竞争的;竞争激烈的;好胜的'),
    ];
    notifier.updateAsrPassRuleCache('HALF');

    // 只说对 1/2：未通过，但应给出"还差 1 个"的进度（说模式释义下方的提示来源）
    await notifier.onAsrResult(jsonEncode({
      'best': '竞争性的',
      'candidates': ['竞争性的'],
      'isFinal': true,
    }));
    var state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, false, reason: '只答对 1/2，不应通过');
    expect(notifier.meaningMatchProgress, (matched: 1, required: 2),
        reason: '未达通过线时应给出"还差几个释义即可通过"的进度');

    // 通过规则放宽为"说出一个意思即可"：已命中 1 个，通过条件此刻已经满足
    notifier.updateAsrPassRuleCache('ONE');

    // 本次输入没有命中任何释义：不能把已达标的题蒙过去
    await notifier.onAsrResult(jsonEncode({
      'best': '香蕉',
      'candidates': ['香蕉'],
      'isFinal': true,
    }));
    state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, false,
        reason: '本次输入未命中任何释义，不应判通过');

    // 重复说出已命中的释义：本次没有"新增"命中，但通过条件已满足，必须判通过。
    // 同一词重新进入环节时会继承上一环节已命中的释义，若只认"新增命中"，用户怎么答都过不去。
    await notifier.onAsrResult(jsonEncode({
      'best': '竞争性的',
      'candidates': ['竞争性的'],
      'isFinal': true,
    }));
    state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, true,
        reason: '重复命中已命中释义时通过条件已满足，应判通过');
    expect(notifier.hasSeenAnswer, true, reason: '通过后答案揭晓，底部渲染「下一词」');
    expect(notifier.meaningMatchProgress, null, reason: '通过后不再展示"还差几个"的进度');
  });

  test('BdcNotifier - 自动 AI 裁判在等待期间本地已命中释义时结果应被丢弃（不得整词放行）', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    // 本用例含 1.5s 以上的真实等待：必须持有监听，避免 autoDispose 在等待期间销毁 notifier
    final keepAlive = container.listen(bdcNotifierProvider, (_, __) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });

    // 用可控的 Completer 替代真实大模型调用，模拟"裁判请求仍在途"
    final judgeCompleter = Completer<Result<String>>();
    AiRefereeUtil.aiChatOverride = (messagesJson, userId) => judgeCompleter.future;
    addTearDown(() => AiRefereeUtil.aiChatOverride = null);

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    container.read(bdcNotifierProvider).wordWrapper!.word.meaningItems = [
      MeaningItemVo.from('a.', '竞争的;竞争激烈的;好胜的'),
    ];
    notifier.updateAsrPassRuleCache('HALF');

    // 说了一句本地完全识别不出的回答 -> 调度自动 AI 裁判兜底
    await notifier.onAsrResult(jsonEncode({
      'best': '苹果香蕉',
      'candidates': ['苹果香蕉'],
      'isFinal': true,
    }));
    expect(notifier.hasPendingWordAiReferee, true, reason: '本地一个都没命中，应调度 AI 裁判兜底');

    // 防抖到期，AI 裁判进入在途等待（大模型尚未返回）
    await Future.delayed(const Duration(milliseconds: 1700));
    expect(container.read(bdcNotifierProvider).isAiEvaluating, true, reason: 'AI 裁判应在途等待');

    // 在途期间本地命中释义："竞争性的" -> "竞争的"
    await notifier.onAsrResult(jsonEncode({
      'best': '竞争性的',
      'candidates': ['竞争性的'],
      'isFinal': true,
    }));
    var state = container.read(bdcNotifierProvider);
    expect(state.wordWrapper!.asrMatchedMeaningItemParts.length, 1);
    expect(state.hasFinishedAnswering, false, reason: '只答对 1/2，尚未通过');

    // AI 裁判此时返回"认可"：因本地已命中，结果必须作废，不能整词放行
    judgeCompleter.complete(Result('200', '', true)
      ..data = '{"isCorrect": true, "intendedMeaning": "竞争性的"}');
    await Future.delayed(const Duration(milliseconds: 100));

    state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, false, reason: 'AI 裁判结果应被丢弃，不得整词放行');
    expect(state.wordWrapper!.aiApprovedAnswer, null, reason: '不应记录 AI 认可回答');
    expect(state.wordWrapper!.asrMatchedMeaningItemParts.length, 1,
        reason: '本地命中结果不应被 AI 整词覆盖');
    expect(state.isAiEvaluating, false, reason: '裁判结束后应复位判定中状态');
  });

  test('BdcNotifier - 英译汉英文拼写板内拼写不应触发释义 AI 裁判', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    container.read(bdcNotifierProvider).wordWrapper!.word.meaningItems = [
      MeaningItemVo.from('a.', '苹果;香蕉;橘子'),
    ];
    notifier.updateAsrPassRuleCache('HALF');

    // 进入英文拼写板（非中文默写）
    notifier.updateShowHandwritingBoard(true);
    var state = container.read(bdcNotifierProvider);
    expect(state.showHandwritingBoard, true);
    expect(state.isChineseDictation, false);

    // 拼写过程中的英文片段：它既不是中文释义，也还没拼对
    notifier.updateMeaningTextWithoutCheck('appl');
    await notifier.checkAsrResult();

    expect(notifier.hasPendingWordAiReferee, false,
        reason: '拼写练习中的英文不是释义答案，不应触发释义 AI 裁判兜底');

    // 拼对后应正常退出手写板返回学习页，且英译汉拼写正确不等于答对该题
    notifier.updateMeaningTextWithoutCheck('apple');
    await notifier.checkAsrResult();
    state = container.read(bdcNotifierProvider);
    expect(state.showHandwritingBoard, false, reason: '拼写正确应退出手写板');
    expect(state.hasFinishedAnswering, false, reason: '拼写正确只是练习，不等于答对英译汉');
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

    // 她/他/它 发音相同，语音识别无法区分，视为完全等同
    expect(notifier.getChineseSentenceMatchScore('他每天早上吃一个苹果。', '她每天早上吃一个苹果。'), 100);
    expect(notifier.getChineseSentenceMatchScore('它很漂亮。', '她很漂亮。'), 100);
    expect(notifier.getChineseSentenceMatchScore('他走了。', '她走了。'), 100);

    // 的/地/得 发音相同 (de)，语音识别无法区分，视为完全等同
    expect(notifier.getChineseSentenceMatchScore('机器精确的切割金属。', '机器精确地切割金属。'), 100);
    expect(notifier.getChineseSentenceMatchScore('他高兴的跳了起来。', '他高兴地跳了起来。'), 100);
    expect(notifier.getChineseSentenceMatchScore('他跑的快。', '他跑得快。'), 100);
    // 混合情况：的同音字全部归一
    expect(notifier.getChineseSentenceMatchScore('她的确跑的很快。', '他的确跑得很快。'), 100);

    // 2. 验证英文句子匹配（ChSentence2En 70% 单词级偏置阈值）
    // 目标：“I eat an apple every morning.” (6个英文单词)
    // 匹对“I eat apple”，分词为 [i, eat, apple]，LCS为 3, 3/6 = 50%
    expect(await notifier.getEnglishSentenceMatchScore('I eat apple', 'I eat an apple every morning.'), 50);
    // 匹对“I eat an apple morning”，分词为 [i, eat, an, apple, morning]，LCS为 5, 5/6 = 83%
    expect(await notifier.getEnglishSentenceMatchScore('I eat an apple morning', 'I eat an apple every morning.'), 83);
    // 匹对“I eat an apple every morning”，LCS单词为 6, 6/6 = 100%
    expect(await notifier.getEnglishSentenceMatchScore('I eat an apple every morning.', 'I eat an apple every morning.'), 100);

    // sb/sth 这类占位缩写：目标句里的 sb/sth 展开为 somebody/something 后再比对，
    // 用户按 somebody or something / somebody and something / somebody something 朗读都应判为通过
    expect(await notifier.getEnglishSentenceMatchScore('let out somebody or something', 'let out sb/sth'), 100);
    expect(await notifier.getEnglishSentenceMatchScore('let out somebody and something', 'let out sb/sth'), 100);
    expect(await notifier.getEnglishSentenceMatchScore('let out somebody something', 'let out sb/sth'), 100);
    // 逆序写法 sth/sb 同样兼容
    expect(await notifier.getEnglishSentenceMatchScore('let out something or somebody', 'let out sth/sb'), 100);

    // 3. 验证智能重叠拼接去重算法 (stitchTexts)
    // 中文无重合拼接
    expect(BdcNotifier.stitchTexts('我每天', '一个苹果', isEnglish: false), '我每天 一个苹果');
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
    // 1. 追加例句步骤(EnSentence2Ch)到答对组,使轨道扩展为 [En2Ch, EnSentence2Ch, List]
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          scope: 'new',
          group: 'correct',
          studyStep: 'EnSentence2Ch',
          seq: 0,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    // 将 word_1 的今日学习次数置为 1,使 StudyBo 计算 stepIndex = todayLearnedTimes = 1(例句步骤)
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(todayLearnedTimes: const Value(1)));
    // 插入"今天首条评分日志"（elapsedDays=0, good）：轨道按答对组扩展
    await db.learningLogsDao.saveEntity(LearningLog(
          id: 'first_log_word_1',
          userId: testUser.id,
          wordId: 'word_1',
          rating: FsrsRating.good.value,
          stability: 2.4,
          difficulty: 3.05,
          elapsedDays: 0,
          scheduledDays: 2,
          createTime: now,
          updateTime: now,
        ), false);
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
          scope: 'new',
          group: 'correct',
          studyStep: 'EnSentence2Ch',
          seq: 0,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(todayLearnedTimes: const Value(1)));
    // 插入"今天首条评分日志"（elapsedDays=0, good）：轨道按答对组扩展为
    // [En2Ch, EnSentence2Ch, List]，stepIndex=1 即例句环节
    await db.learningLogsDao.saveEntity(LearningLog(
          id: 'first_log_word_1',
          userId: testUser.id,
          wordId: 'word_1',
          rating: FsrsRating.good.value,
          stability: 2.4,
          difficulty: 3.05,
          elapsedDays: 0,
          scheduledDays: 2,
          createTime: now,
          updateTime: now,
        ), false);
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
    expect(notifier.sentenceAnswerController.text, '我每天都吃早上',
        reason: '补充内容应插入光标处,锚点前后文本保留');
    await notifier.stopPttAsr();
    await Future.delayed(const Duration(milliseconds: 50));
    expect(container.read(bdcNotifierProvider).isPttPressed, false);

    await Future.delayed(const Duration(milliseconds: 100));
  });

  test('进入单词时加载 learningHistoryFuture(历史测评日志)', () async {
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          scope: 'new',
          group: 'correct',
          studyStep: 'EnSentence2Ch',
          seq: 0,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(todayLearnedTimes: const Value(1)));
    // 插入"今天首条评分日志"（elapsedDays=0, good）：轨道按答对组扩展为
    // [En2Ch, EnSentence2Ch, List]，stepIndex=1 即例句环节
    await db.learningLogsDao.saveEntity(LearningLog(
          id: 'first_log_word_1',
          userId: testUser.id,
          wordId: 'word_1',
          rating: FsrsRating.good.value,
          stability: 2.4,
          difficulty: 3.05,
          elapsedDays: 0,
          scheduledDays: 2,
          createTime: now,
          updateTime: now,
        ), false);
    await db.into(db.sentences).insert(Sentence(
          id: 'snt_6',
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

    // handleWord 后 learningHistoryFuture 应被赋值(不再为 null)
    expect(notifier.learningHistoryFuture, isNot(null),
        reason: '进入单词时应加载历史测评日志,供巩固环节显示测评得分');

    await Future.delayed(const Duration(milliseconds: 100));
  });

  test('例句环节 PTT:Android 累积全文事件流(识别中途改写)不产生大段重复', () async {
    // 回归用例:Android sherpa-onnx 与 iOS SFSpeechRecognizer 发送的都是"累积全文"
    // (从会话开始到当前的完整文本)。按住期间若识别器中途改写已输出内容
    // (如 "displine" → "discipline"),对累积全文做 stitchTexts 重叠拼接会把
    // 旧全文与改写后的新全文错误串接 → 整句重复。正确行为:按住期间以空基准
    // 直接覆盖为最新全文,仅跨段(endpoint reset 后新段落)才拼接。
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          scope: 'new',
          group: 'correct',
          studyStep: 'EnSentence2Ch',
          seq: 0,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(todayLearnedTimes: const Value(1)));
    // 插入"今天首条评分日志"（elapsedDays=0, good）：轨道按答对组扩展为
    // [En2Ch, EnSentence2Ch, List]，stepIndex=1 即例句环节
    await db.learningLogsDao.saveEntity(LearningLog(
          id: 'first_log_word_1',
          userId: testUser.id,
          wordId: 'word_1',
          rating: FsrsRating.good.value,
          stability: 2.4,
          difficulty: 3.05,
          elapsedDays: 0,
          scheduledDays: 2,
          createTime: now,
          updateTime: now,
        ), false);
    await db.into(db.sentences).insert(Sentence(
          id: 'snt_7',
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
    await notifier.loadData(FakeBuildContext());
    expect(container.read(bdcNotifierProvider).studyStep, 'EnSentence2Ch');

    notifier.startPttAsr();
    for (var i = 0; i < 20 && mockAsr.startAsrCallCount < 1; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // 模拟累积全文事件流(每次事件是完整文本,识别中途改写):
    // 1. 初始识别 "我每天早上吃一个苹果"
    await notifier.onAsrResult(jsonEncode({
      'best': '我每天早上吃一个苹果',
      'candidates': ['我每天早上吃一个苹果'],
      'isFinal': false,
    }));
    // 2. 识别器追加 "和香蕉" → 完整文本
    await notifier.onAsrResult(jsonEncode({
      'best': '我每天早上吃一个苹果和香蕉',
      'candidates': ['我每天早上吃一个苹果和香蕉'],
      'isFinal': false,
    }));
    // 3. 识别器中途改写:去掉"和" → 完整文本
    await notifier.onAsrResult(jsonEncode({
      'best': '我每天早上吃一个苹果香蕉',
      'candidates': ['我每天早上吃一个苹果香蕉'],
      'isFinal': false,
    }));

    // 累积文本必须等于最新完整文本,不得把旧全文与改写后的新全文串接重复
    final accumulated = notifier.sentenceAnswerController.text.trim();
    expect(accumulated, '我每天早上吃一个苹果香蕉',
        reason: '累积全文事件流应直接覆盖为最新完整文本,不得拼接出重复: 实际 "$accumulated"');
    // 不包含任何重复片段(如 "苹果和香蕉我每天早上" 之类)
    expect(accumulated.split('我每天').length, 2,
        reason: '旧全文与新全文不得被同时保留: 实际 "$accumulated"');

    await notifier.stopPttAsr();
    await Future.delayed(const Duration(milliseconds: 100));
  });

  test('BdcNotifier - updateFsrsRating 修改评分后:同步 assessmentRating、持久化 LearningLog 并刷新 learningHistoryFuture', () async {
    // 准备:插入一条已有 LearningLog(模拟测评环节已提交评分 good)
    final today = AppClock.today();
    final testNow = today.add(const Duration(hours: 10));
    AppClock.setClock(FakeClock(testNow));
    addTearDown(AppClock.reset);
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_1',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.good.value,
      stability: 1.0,
      difficulty: 5.0,
      elapsedDays: 0,
      scheduledDays: 3,
      createTime: testNow,
      updateTime: testNow,
    ), false);
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
    await notifier.loadData(FakeBuildContext());
    var state = container.read(bdcNotifierProvider);
    expect(state.word!.spell, 'apple');

    // 修改评分为 easy
    notifier.updateFsrsRating(FsrsRating.easy);
    state = container.read(bdcNotifierProvider);
    expect(state.lastFsrsRating, FsrsRating.easy);

    // 等待异步持久化完成
    List<LearningLog> logs = [];
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      logs = await db.learningLogsDao.getHistory(testUser.id, 'word_1');
      if (logs.isNotEmpty && logs.first.rating == FsrsRating.easy.value) break;
    }

    // LearningLog 当天首条日志已持久化更新为 easy（本用例今天只有这一条）
    expect(logs, isNotEmpty, reason: '应有 LearningLog 记录');
    expect(logs.first.rating, FsrsRating.easy.value,
        reason: '修改评分后 LearningLog 当天首条日志应为新评分,实际为 ${logs.first.rating}');

    // learningHistoryFuture 已刷新:解析后当天首条日志为新评分
    final futureLogs = await notifier.learningHistoryFuture;
    expect(futureLogs, isNot(null));
    expect(futureLogs!.first.rating, FsrsRating.easy.value,
        reason: 'learningHistoryFuture 刷新后应返回新评分');

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('BdcNotifier - 修改今日评分:新词(仅测评一次)改评分应重新 init 计算下次复习天数', () async {
    // 模拟新词已完成测评提交(easy):stability=init(easy)的结果 15.69105,reps=1
    final today = AppClock.today();
    final testNow = today.add(const Duration(hours: 10));
    AppClock.setClock(FakeClock(testNow));
    addTearDown(AppClock.reset);
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(
          stability: const Value(15.69105),
          difficulty: const Value(3.2245015893713678),
          reps: const Value(1),
          scheduledDays: const Value(16),
          state: const Value(1), // Learning
        ));
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_easy_1',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: 15.69105,
      difficulty: 3.2245015893713678,
      elapsedDays: 0,
      scheduledDays: 16,
      createTime: testNow,
      updateTime: testNow,
    ), false);
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
    await notifier.loadData(FakeBuildContext());
    var state = container.read(bdcNotifierProvider);
    expect(state.word!.spell, 'apple');

    // 把 easy 改成 good:新词应重新 init(good),下次复习 = init(good).scheduledDays = 3 天
    notifier.updateFsrsRating(FsrsRating.good);
    // 等待异步计算与持久化完成
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      state = container.read(bdcNotifierProvider);
      if (state.fsrsItem != null && state.fsrsItem!.scheduledDays == 3) break;
    }
    expect(state.fsrsItem, isNot(null));
    expect(state.fsrsItem!.scheduledDays, 3,
        reason: '新词改评分应重新 init 计算,预期 3 天,实际 ${state.fsrsItem!.scheduledDays}');

    // LearningLog 的 scheduledDays 也应更新为 init(good) 的结果
    final logs = await db.learningLogsDao.getHistory(testUser.id, 'word_1');
    expect(logs, isNotEmpty);
    expect(logs.first.scheduledDays, 3,
        reason: 'LearningLog 持久化的下次复习天数应为 init(good) 的 3 天,实际 ${logs.first.scheduledDays}');

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('BdcNotifier - 修改今日评分:多环节后新词改评分应重放全部当天环节', () async {
    // 模拟今天的新词已完成测评(easy)+巩固(good)两个环节提交：
    // 真实状态是 init(easy)=15.69105 再走同日短期公式 next(good,0) ≈ 22.09
    final today = AppClock.today();
    final testNow = today.add(const Duration(hours: 10));
    AppClock.setClock(FakeClock(testNow));
    addTearDown(AppClock.reset);
    const consolidateStability = 22.089408519007495; // 15.69105 * e^(w17*(3-3+w18))
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(
          stability: const Value(consolidateStability),
          difficulty: const Value(3.2245015893713673),
          reps: const Value(2),
          scheduledDays: const Value(22),
          state: const Value(2), // Review(已过巩固)
        ));
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_easy_multi_1',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: 15.69105,
      difficulty: 3.2245015893713678,
      elapsedDays: 0,
      scheduledDays: 16,
      createTime: testNow,
      updateTime: testNow,
    ), false);
    // 巩固环节：同日第二次评分，elapsedDays=0 走短期公式
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_easy_multi_2',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.good.value,
      stability: consolidateStability,
      difficulty: 3.2245015893713673,
      elapsedDays: 0,
      scheduledDays: 22,
      createTime: testNow.add(const Duration(seconds: 30)),
      updateTime: testNow.add(const Duration(seconds: 30)),
    ), false);
    // 该词今天之前无任何学习记录(纯新词,仅今天学习)
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
    await notifier.loadData(FakeBuildContext());
    var state = container.read(bdcNotifierProvider);
    expect(state.word!.spell, 'apple');

    // 把测评的 easy 改成 good：新词重新 init(good)，再由巩固环节的 good 走同日短期公式
    // init(good)=3.173 → ×e^(w17*(3-3+w18)) ≈ 4.467 → 4 天（旧口径只看首条，会给 3 天）
    notifier.updateFsrsRating(FsrsRating.good);
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      state = container.read(bdcNotifierProvider);
      if (state.fsrsItem != null && state.fsrsItem!.scheduledDays == 4) break;
    }
    expect(state.fsrsItem, isNot(null));
    expect(state.fsrsItem!.scheduledDays, 4,
        reason: '多环节后新词改评分必须重放全部当天环节,预期 4 天,实际 ${state.fsrsItem!.scheduledDays}');

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('BdcNotifier - 修改今日评分:复习词改评分应重放测评+巩固全部当天环节', () async {
    // 模拟复习词:昨天加入(addTime=昨天)、昨天学过(stability=15.69105, scheduledDays=16)
    final today = AppClock.today();
    final testNow = today.add(const Duration(hours: 10));
    AppClock.setClock(FakeClock(testNow));
    addTearDown(AppClock.reset);
    final yesterday = today.subtract(const Duration(days: 1));
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(
          stability: const Value(35.21175712420889), // 测评 easy 后再巩固 good 的真实状态
          difficulty: const Value(2.135155608561961),
          reps: const Value(2),
          scheduledDays: const Value(35),
          state: const Value(2), // Review
          addTime: Value(yesterday),
          addDay: const Value(2),
          isTodayNewWord: const Value(false),
          lastLearningDate: Value(yesterday),
          learnedTimes: const Value(1),
          todayLearnedTimes: const Value(0),
        ));
    // 昨天(测评前)的记录
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_yesterday',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: 15.69105,
      difficulty: 3.2245015893713678,
      elapsedDays: 5,
      scheduledDays: 16,
      createTime: yesterday,
      updateTime: yesterday,
    ), false);
    // 今天测评提交的记录(当天首条,评分修正对话框改的就是它)
    // 注意:测评 easy 是 next(测评前状态=15.69105, easy, elapsedDays=1) 的结果,
    // 真实 FSRS 计算 stability≈25.01, scheduledDays=25
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_today_assess',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: 25.012414485811277,
      difficulty: 2.1301214599670124,
      elapsedDays: 1,
      scheduledDays: 25,
      createTime: testNow,
      updateTime: testNow,
    ), false);
    // 今天的巩固环节(当天第二条,elapsedDays=0 走 FSRS-5 短期公式):S 从 25.01 抬到 35.21
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_today_consolidate',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.good.value,
      stability: 35.21175712420889,
      difficulty: 2.135155608561961,
      elapsedDays: 0,
      scheduledDays: 35,
      createTime: testNow.add(const Duration(seconds: 30)),
      updateTime: testNow.add(const Duration(seconds: 30)),
    ), false);
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
    await notifier.loadData(FakeBuildContext());
    var state = container.read(bdcNotifierProvider);
    expect(state.word!.spell, 'apple');

    // 把测评的 easy 改成 good：先按测评前状态 next(15.69105, good, elapsedDays=1) ≈ 18.81，
    // 再把当天巩固环节的 good 按同日短期公式抬升 ×e^(w17*(3-3+w18)) ≈ 26.48 → 26 天。
    // 旧口径只重放当天首条（停在 19 天），漏掉了巩固环节的真实推进。
    notifier.updateFsrsRating(FsrsRating.good);
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      state = container.read(bdcNotifierProvider);
      if (state.fsrsItem != null && state.fsrsItem!.scheduledDays == 26) break;
    }
    expect(state.fsrsItem, isNot(null));
    expect(state.fsrsItem!.scheduledDays, 26,
        reason: '复习词改评分必须重放测评+巩固全部当天环节,预期 26 天,实际 ${state.fsrsItem!.scheduledDays}');

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('BdcNotifier - 修改今日评分:计数基准取 learning_words 当前行,不取陈旧的界面快照', () async {
    // 复习词：昨天学过（日志记着测评前的记忆状态），今天这次测评的评分刚刚提交
    final today = AppClock.today();
    final testNow = today.add(const Duration(hours: 10));
    AppClock.setClock(FakeClock(testNow));
    addTearDown(AppClock.reset);
    final yesterday = today.subtract(const Duration(days: 1));
    final fsrs = FSRS();

    // 今天之前的记忆状态（学习进度行与昨天的日志同源）：reps=2
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(
          stability: const Value(15.69105),
          difficulty: const Value(3.2245015893713678),
          reps: const Value(2),
          scheduledDays: const Value(16),
          state: const Value(2), // Review
          addTime: Value(yesterday),
          addDay: const Value(2),
          isTodayNewWord: const Value(false),
          lastLearningDate: Value(yesterday),
          learnedTimes: const Value(1),
          todayLearnedTimes: const Value(0),
        ));
    // 昨天(测评前)的日志：重放基准的来源
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_stale_yesterday',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: 15.69105,
      difficulty: 3.2245015893713678,
      elapsedDays: 5,
      scheduledDays: 16,
      createTime: yesterday,
      updateTime: yesterday,
    ), false);
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
    await notifier.loadData(FakeBuildContext());
    var state = container.read(bdcNotifierProvider);
    expect(state.word!.spell, 'apple');
    // 界面快照停在"今天这次评分提交之前"：reps=2
    expect(state.currentGetWordResult!.learningWord!.reps, 2,
        reason: '前置条件：界面快照必须是提交前的状态');

    // 模拟"今天这次测评已经提交"：库里的行前进到评分之后的状态（reps 2 → 3），并写下当天首条日志
    final beforeToday = FSRSItem(
      stability: 15.69105,
      difficulty: 3.2245015893713678,
      elapsedDays: 0,
      scheduledDays: 16,
      reps: 2,
      lapses: 0,
      state: FsrsState.review,
    );
    final submitted = fsrs.next(beforeToday, FsrsRating.easy, 2);
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(
          stability: Value(submitted.stability),
          difficulty: Value(submitted.difficulty),
          reps: Value(submitted.reps),
          scheduledDays: Value(submitted.scheduledDays),
          state: Value(submitted.state.value),
          lastLearningDate: Value(today),
          learnedTimes: const Value(2),
          todayLearnedTimes: const Value(1),
        ));
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_stale_today_assess',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: submitted.stability,
      difficulty: submitted.difficulty,
      elapsedDays: 2,
      scheduledDays: submitted.scheduledDays,
      createTime: testNow,
      updateTime: testNow,
    ), false);
    expect(submitted.reps, 3, reason: '前置条件：库里的行已推进到 reps=3');

    // 把测评的 easy 改成 good：基准必须用数据库当前行（reps=3）回推，而不是陈旧的快照（reps=2）
    // 正确：基准 reps = 3 - 1 = 2 → 末态 reps = 3（与库里当前行一致）
    // 错误：基准 reps = 2 - 1 = 1 → 末态 reps = 2，把库里已推进的次数写回去倒退一位
    final expected = fsrs.next(beforeToday, FsrsRating.good, 2);
    notifier.updateFsrsRating(FsrsRating.good);
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      state = container.read(bdcNotifierProvider);
      if (state.fsrsItem != null && state.fsrsItem!.reps == expected.reps) break;
    }
    expect(state.fsrsItem, isNot(null));
    expect(state.fsrsItem!.stability, closeTo(expected.stability, 1e-9));
    expect(state.fsrsItem!.difficulty, closeTo(expected.difficulty, 1e-9));
    expect(state.fsrsItem!.scheduledDays, expected.scheduledDays);
    expect(state.fsrsItem!.lapses, expected.lapses);
    expect(state.fsrsItem!.reps, 3,
        reason: '重放末态的 reps 必须等于"从数据库当前行重放"的结果；写成 2 就是取了陈旧界面快照');

    // 落库的学习进度同样是"从数据库当前行重放"的结果
    final lw = await db.learningWordsDao.getById(testUser.id, 'word_1');
    expect(lw!.reps, 3, reason: 'learning_words 的 reps 不得被写回 2');
    expect(lw.stability, closeTo(expected.stability, 1e-9));

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('BdcNotifier - 修改今日评分:重算稳定度跌破掌握线,词被移出「已掌握」词书并回到学习中', () async {
    // 该词学习进度记着真实的毕业稳定度 150.0；模拟它今天刚毕业进入「已掌握」词书，
    // 用户在回看里打开它并把今天的测评评分改低
    final today = AppClock.today();
    final testNow = today.add(const Duration(hours: 10));
    AppClock.setClock(FakeClock(testNow));
    addTearDown(AppClock.reset);
    final yesterday = today.subtract(const Duration(days: 1));
    final fsrs = FSRS();

    const masteredDictId = 'mock_dict_mastered';
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
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(
          stability: const Value(150.0),
          difficulty: const Value(5.0),
          reps: const Value(4),
          scheduledDays: const Value(150),
          state: const Value(2), // Review
          addTime: Value(yesterday),
          addDay: const Value(2),
          isTodayNewWord: const Value(false),
          lastLearningDate: Value(today),
          learnedTimes: const Value(5),
          todayLearnedTimes: const Value(0),
        ));
    // 昨天(测评前)的日志 + 今天已提交的测评日志（当天首条，改评分改的就是它）
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_revoke_yesterday',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: 140.0,
      difficulty: 5.0,
      elapsedDays: 3,
      scheduledDays: 140,
      createTime: yesterday,
      updateTime: yesterday,
    ), false);
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_revoke_today',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: 150.0,
      difficulty: 5.0,
      elapsedDays: 2,
      scheduledDays: 150,
      createTime: testNow,
      updateTime: testNow,
    ), false);
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

    // 进入回看：拿到这个词的界面快照（此时词还没进「已掌握」词书，否则今日计划不会出题）
    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());
    final state0 = container.read(bdcNotifierProvider);
    expect(state0.word!.spell, 'apple');
    expect(state0.currentGetWordResult!.learningWord!.stability, 150.0);

    // 它在今天毕业：走真实的毕业入口写「已掌握」词书并同步缓存
    await StudyCacheManager().saveMasteredWordAndSync(db, testUser.id, 'word_1');
    final masteredIdsBefore = await StudyCacheManager().getMasteredWordIds(db, testUser.id);
    expect(masteredIdsBefore.contains('word_1'), true,
        reason: '前置条件：这个词现在算已掌握，已从今日计划候选池排除');
    final todayWordsBefore = await StudyCacheManager().getTodayWords(db, testUser.id);
    expect(
        todayWordsBefore
            .where((w) => !w.isEffectivelyMastered(masteredIdsBefore))
            .map((w) => w.wordId)
            .toList(),
        isNot(contains('word_1')),
        reason: '前置条件：已掌握的词不出现在今日计划候选池里');

    // 前置条件：把今天的测评从 easy 改成 again，重放稳定度必须跌破掌握线
    final expectedReplayed = fsrs.next(
      FSRSItem(
        stability: 140.0,
        difficulty: 5.0,
        elapsedDays: 0,
        scheduledDays: 140,
        reps: 3, // 当前行 reps 4 − 当天 1 条日志
        lapses: 0,
        state: FsrsState.review,
      ),
      FsrsRating.again,
      2,
    );
    expect(expectedReplayed.stability, lessThan(Constants.graduationStability),
        reason: '前置条件：重算稳定度必须低于掌握线才会退出已掌握');

    notifier.updateFsrsRating(FsrsRating.again);
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      if (!await db.masteredWordsDao.isWordMastered(testUser.id, 'word_1')) break;
    }
    final state = container.read(bdcNotifierProvider);

    // ① 词已不在「已掌握」词书：词条行、词书词数、用户已掌握计数一并更新
    expect(await db.masteredWordsDao.isWordMastered(testUser.id, 'word_1'), false,
        reason: '重算稳定度跌破掌握线后，词必须移出「已掌握」词书');
    expect(await db.dictWordsDao.getDictWordCount(masteredDictId), 0,
        reason: '「已掌握」词书的词数要同步减一');
    final user = await db.usersDao.getUserById(testUser.id);
    expect(user!.masteredWordsCount, 0, reason: '用户的已掌握计数要同步更新');

    // ② 学习进度记录仍在，且稳定度是真实重算值（低于掌握线）
    final lw = await db.learningWordsDao.getById(testUser.id, 'word_1');
    expect(lw, isNot(null), reason: '改评分打回"学习中"必须保留学习进度记录');
    expect(lw!.stability, closeTo(expectedReplayed.stability, 1e-9),
        reason: '学习进度写的是重放算出的真实稳定度，不是掌握线哨兵值');
    expect(lw.stability, lessThan(Constants.graduationStability));
    expect(state.fsrsItem!.stability, closeTo(expectedReplayed.stability, 1e-9));

    // ③ 词重新回到今日计划候选池（口径 = 用户全部学习进度记录 − 「已掌握」词书成员）
    final todayWords = await StudyCacheManager().getTodayWords(db, testUser.id);
    final masteredIds = await StudyCacheManager().getMasteredWordIds(db, testUser.id);
    expect(masteredIds.contains('word_1'), false, reason: '已掌握 ID 缓存也要同步移除该词');
    expect(
        todayWords
            .where((w) => !w.isEffectivelyMastered(masteredIds))
            .map((w) => w.wordId)
            .toList(),
        contains('word_1'),
        reason: '移出已掌握后该词必须重新进入今日计划候选池');
    expect(await db.learningWordsDao.getLearningWordIdSet(testUser.id, ['word_1']),
        contains('word_1'),
        reason: 'DAO 口径同样把这个词算作"学习中"（学习进度行仍在且已不在已掌握词书）');

    // ④ 埋点 AnalyticsUtil.trackMasteredRevokedByRating 在本用例中无法观测：
    //    AnalyticsUtil 是纯静态类，trackEvent 先看隐私授权 _canTrack，且只在 Android/iOS 上
    //    真正上报（见 lib/util/analytics_util.dart:15-35），项目没有可注入的埋点替身或事件队列，
    //    故这里只断言上面三条，埋点由代码路径保证（lib/api/bo/study_bo.dart 的 _revokeMasteredIfBelowGraduation）。

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('BdcNotifier - 修改今日评分:重选当前评分幂等(不改 stability/reps/lapses)', () async {
    // 复习词：昨天学过 → 今天测评 easy（当天首条）+ 巩固 good（当天第二条）
    final today = AppClock.today();
    final testNow = today.add(const Duration(hours: 10));
    AppClock.setClock(FakeClock(testNow));
    addTearDown(AppClock.reset);
    final yesterday = today.subtract(const Duration(days: 1));
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(
          stability: const Value(35.21175712420889),
          difficulty: const Value(2.135155608561961),
          reps: const Value(2),
          lapses: const Value(0),
          scheduledDays: const Value(35),
          state: const Value(2),
          addTime: Value(yesterday),
          addDay: const Value(2),
          isTodayNewWord: const Value(false),
          lastLearningDate: Value(yesterday),
        ));
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_idem_yesterday',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: 15.69105,
      difficulty: 3.2245015893713678,
      elapsedDays: 5,
      scheduledDays: 16,
      createTime: yesterday,
      updateTime: yesterday,
    ), false);
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_idem_assess',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: 25.012414485811277,
      difficulty: 2.1301214599670124,
      elapsedDays: 1,
      scheduledDays: 25,
      createTime: testNow,
      updateTime: testNow,
    ), false);
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_idem_consolidate',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.good.value,
      stability: 35.21175712420889,
      difficulty: 2.135155608561961,
      elapsedDays: 0,
      scheduledDays: 35,
      createTime: testNow.add(const Duration(seconds: 30)),
      updateTime: testNow.add(const Duration(seconds: 30)),
    ), false);
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
    await notifier.loadData(FakeBuildContext());
    var state = container.read(bdcNotifierProvider);
    expect(state.word!.spell, 'apple');

    // 重选与"今日测评"完全相同的 easy：重放必须精确复现现有状态，不产生任何漂移
    notifier.updateFsrsRating(FsrsRating.easy);
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      state = container.read(bdcNotifierProvider);
      if (state.fsrsItem != null && state.fsrsItem!.scheduledDays == 35) break;
    }
    expect(state.fsrsItem, isNot(null));
    expect(state.fsrsItem!.scheduledDays, 35);
    expect(state.fsrsItem!.stability, closeTo(35.21175712420889, 1e-9));
    expect(state.fsrsItem!.reps, 2, reason: '重放条数与基准 reps 回推后应等于现状');
    expect(state.fsrsItem!.lapses, 0);

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('BdcNotifier - 修改今日评分:连续修改(good->easy->hard)结果稳定不漂移', () async {
    // 今日新词(addTime=今天), 模拟测评 easy 提交
    final today = AppClock.today();
    final testNow = today.add(const Duration(hours: 10));
    AppClock.setClock(FakeClock(testNow));
    addTearDown(AppClock.reset);
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(
          stability: const Value(15.69105),
          difficulty: const Value(3.2245015893713678),
          reps: const Value(1),
          scheduledDays: const Value(16),
          state: const Value(1), // Learning
        ));
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_easy_stable_1',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: 15.69105,
      difficulty: 3.2245015893713678,
      elapsedDays: 0,
      scheduledDays: 16,
      createTime: testNow,
      updateTime: testNow,
    ), false);
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
    await notifier.loadData(FakeBuildContext());
    var state = container.read(bdcNotifierProvider);
    expect(state.word!.spell, 'apple');

    // good -> 3 天 (init(good)=3.173)
    notifier.updateFsrsRating(FsrsRating.good);
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      state = container.read(bdcNotifierProvider);
      if (state.fsrsItem != null && state.fsrsItem!.scheduledDays == 3) break;
    }
    expect(state.fsrsItem!.scheduledDays, 3,
        reason: '第一次改 good 应为 3 天,实际 ${state.fsrsItem!.scheduledDays}');

    // 再改 easy -> 16 天 (init(easy)=15.69105)
    notifier.updateFsrsRating(FsrsRating.easy);
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      state = container.read(bdcNotifierProvider);
      if (state.fsrsItem != null && state.fsrsItem!.scheduledDays == 16) break;
    }
    expect(state.fsrsItem!.scheduledDays, 16,
        reason: '再改 easy 应为 16 天,实际 ${state.fsrsItem!.scheduledDays}');

    // 再改 hard -> 1 天 (init(hard)=1.18385)
    notifier.updateFsrsRating(FsrsRating.hard);
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      state = container.read(bdcNotifierProvider);
      if (state.fsrsItem != null && state.fsrsItem!.scheduledDays == 1) break;
    }
    expect(state.fsrsItem!.scheduledDays, 1,
        reason: '再改 hard 应为 1 天,实际 ${state.fsrsItem!.scheduledDays}');

    // 改回 easy -> 16 天 (不漂移!)
    notifier.updateFsrsRating(FsrsRating.easy);
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      state = container.read(bdcNotifierProvider);
      if (state.fsrsItem != null && state.fsrsItem!.scheduledDays == 16) break;
    }
    expect(state.fsrsItem!.scheduledDays, 16,
        reason: '改回 easy 应稳定回到 16 天,实际 ${state.fsrsItem!.scheduledDays}');

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('BdcNotifier - 修改今日评分:连续改 good→easy→hard→easy 不漂移,只改当天首条日志', () async {
    // 复习词：昨天学过（测评前基准 15.69105），今天测评 easy（当天首条）+ 巩固 good（当天第二条）。
    // 巩固日志的存在正是旧的"替换最新一条"口径会踩的坑：改评分落到了巩固日志上，
    // 当天首条仍是旧评分，反复修改互相污染（实测 good→easy→hard→easy 天数 4→22→3→13）。
    final today = AppClock.today();
    final testNow = today.add(const Duration(hours: 10));
    AppClock.setClock(FakeClock(testNow));
    addTearDown(AppClock.reset);
    final yesterday = today.subtract(const Duration(days: 1));
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(
          stability: const Value(35.21175712420889),
          difficulty: const Value(2.135155608561961),
          reps: const Value(2),
          lapses: const Value(0),
          scheduledDays: const Value(35),
          state: const Value(2), // Review
          addTime: Value(yesterday),
          addDay: const Value(2),
          isTodayNewWord: const Value(false),
          lastLearningDate: Value(yesterday),
          // 学习步骤次数：修改评分全程不得改动（todayLearnedTimes 保持 0，
          // 否则会被 getWord 的"跨天残留进度"防线拦下）
          learnedTimes: const Value(3),
          todayLearnedTimes: const Value(0),
        ));
    // 昨天(测评前)的日志 → 重放基准
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_drift_yesterday',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: 15.69105,
      difficulty: 3.2245015893713678,
      elapsedDays: 5,
      scheduledDays: 16,
      createTime: yesterday,
      updateTime: yesterday,
    ), false);
    // 今天测评(当天首条,评分修正对话框改的就是它)：next(15.69105, easy, 1) ≈ 25.0124 → 25 天
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_drift_assess',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.easy.value,
      stability: 25.012414485811277,
      difficulty: 2.1301214599670124,
      elapsedDays: 1,
      scheduledDays: 25,
      createTime: testNow,
      updateTime: testNow,
    ), false);
    // 今天巩固(当天第二条)：next(25.0124, good, 0) ≈ 35.2118 → 35 天
    await db.learningLogsDao.saveEntity(LearningLog(
      id: 'log_drift_consolidate',
      userId: testUser.id,
      wordId: 'word_1',
      rating: FsrsRating.good.value,
      stability: 35.21175712420889,
      difficulty: 2.135155608561961,
      elapsedDays: 0,
      scheduledDays: 35,
      createTime: testNow.add(const Duration(seconds: 30)),
      updateTime: testNow.add(const Duration(seconds: 30)),
    ), false);
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
    await notifier.loadData(FakeBuildContext());
    var state = container.read(bdcNotifierProvider);
    expect(state.word!.spell, 'apple');

    Future<LearningLog> logById(String id) async {
      final logs = await db.learningLogsDao.getHistory(testUser.id, 'word_1');
      return logs.firstWhere((l) => l.id == id);
    }

    // 连续改评分：每次都只能落在"当天首条日志"上，巩固日志的评分与状态纹丝不动
    for (final rating in [
      FsrsRating.good,
      FsrsRating.easy,
      FsrsRating.hard,
      FsrsRating.easy
    ]) {
      notifier.updateFsrsRating(rating);
      for (int i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 20));
        if ((await logById('log_drift_assess')).rating == rating.value) break;
      }
      final assessLog = await logById('log_drift_assess');
      expect(assessLog.rating, rating.value,
          reason: '当天首条日志的评分应更新为 ${rating.label},实际 ${assessLog.rating}');
      expect(assessLog.elapsedDays, 1,
          reason: '首条日志只能写重放首步态：跨天测评的 elapsedDays 应保留原间隔 1；'
              '若写成末态会得到 0，下次重放就会误走同日短期公式');
      final consolidateLog = await logById('log_drift_consolidate');
      expect(consolidateLog.rating, FsrsRating.good.value,
          reason: '巩固日志的评分必须保持原值,不能被新评分污染');
      expect(consolidateLog.stability, closeTo(35.21175712420889, 1e-9));
      expect(consolidateLog.scheduledDays, 35);
    }

    // 当天首条日志 = 首步态：next(15.69105, easy, 1) ≈ 25.0124 → 25 天（不是末态的 35.2118/35）
    final assessLog = await logById('log_drift_assess');
    expect(assessLog.stability, closeTo(25.012414485811277, 1e-9));
    expect(assessLog.scheduledDays, 25);

    // learning_words = 末态，且与"一次性改成 easy"完全一致（重放：首条 easy + 巩固 good）
    state = container.read(bdcNotifierProvider);
    expect(state.fsrsItem!.stability, closeTo(35.21175712420889, 1e-9),
        reason: '连续修改后不得漂移');
    expect(state.fsrsItem!.scheduledDays, 35);
    expect(state.fsrsItem!.reps, 2);
    expect(state.fsrsItem!.lapses, 0);

    final lw = await (db.select(db.learningWords)
          ..where((t) => t.userId.equals(testUser.id) & t.wordId.equals('word_1')))
        .getSingle();
    expect(lw.stability, closeTo(35.21175712420889, 1e-9));
    expect(lw.scheduledDays, 35);
    expect(lw.reps, 2);
    expect(lw.lapses, 0);
    expect(lw.learnedTimes, 3, reason: '修改评分不得改动学习步骤次数');
    expect(lw.todayLearnedTimes, 0, reason: '修改评分不得改动今日学习步骤次数');
    expect((await db.learningLogsDao.getHistory(testUser.id, 'word_1')).length, 3,
        reason: '连续修改只应原地替换当天首条日志,不得新增或丢失日志');

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('BdcNotifier - 详情页 FSRS 预览按当前词现算天数，不残留上一个词', () async {
    // word_1 是昨天学过的复习词。若预览沿用 state.daysSinceLastReview（默认 null→0），
    // 会把跨天复习误当同日评分走短期公式，S 被错误缩放（15.69→22.09 而不是 18.81）
    final today = AppClock.today();
    final yesterday = today.subtract(const Duration(days: 1));
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(
          stability: const Value(15.69105),
          difficulty: const Value(3.2245015893713678),
          reps: const Value(1),
          scheduledDays: const Value(16),
          state: const Value(2), // Review
          isTodayNewWord: const Value(false),
          lastLearningDate: Value(yesterday),
        ));
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
    await notifier.loadData(FakeBuildContext());
    final loaded = container.read(bdcNotifierProvider);
    expect(loaded.word!.spell, 'apple');
    expect(loaded.daysSinceLastReview == null, isTrue,
        reason: 'handleWord 必须把 daysSinceLastReview 重置为 null，避免跨词残留');

    // 触发详情页预览（预览在跳转路由前同步写入 fsrsItem，无需等待路由返回）
    unawaited(notifier.showWordDetail(loaded.word!, false, null,
        fsrsRating: FsrsRating.good));
    final preview = container.read(bdcNotifierProvider).fsrsItem;
    expect(preview, isNot(null));
    expect(preview!.scheduledDays, 19,
        reason: '跨天复习预览应按 elapsedDays=1 走长期公式(19 天)，而非同日短期公式(22 天)');

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('BdcNotifier - 复习词测评答错进入恢复环节(isRestoreStep)→答对进入列表页', () async {
    // word_1 改造成复习词：昨天学过、scheduledDays=2、state=review（只改 word_1）
    final yesterday = now.subtract(const Duration(days: 1));
    await (db.update(db.learningWords)
          ..where((lw) => lw.userId.equals(testUser.id) & lw.wordId.equals('word_1')))
        .write(LearningWordsCompanion(
          isTodayNewWord: const Value(false),
          stability: const Value(2.4),
          difficulty: const Value(3.05),
          elapsedDays: const Value(0),
          scheduledDays: const Value(2),
          reps: const Value(1),
          lapses: const Value(0),
          state: const Value(2),
          lastLearningDate: Value(yesterday),
          todayLearnedTimes: const Value(0),
        ));
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
    await notifier.loadData(FakeBuildContext());
    // 组进度由 handleWord 里的异步刷新落定（unawaited 调用）
    await _waitUntil(container, (s) => s.groupStepTrackName != null);
    var state = container.read(bdcNotifierProvider);
    expect(state.groupStepTrackName, '旧词测评',
        reason: '测评环节尚未评分，当前词轨道名为"旧词测评"');

    // 测评答错 → 应进入恢复环节
    // 先受理这次作答（与线上判题链路一致），再提交流转
    notifier.acceptAnswerForTesting(FsrsRating.again);
    await notifier.getNextWord(true, fsrsRating: FsrsRating.again);
    state = container.read(bdcNotifierProvider);
    expect(state.currentGetWordResult!.stepIndex, 0,
        reason: '答错不推进：留在测评环节重练，答对后才进入恢复环节');
    expect(state.currentGetWordResult!.learningWord!.state, FsrsState.relearning.value,
        reason: '首答答错仍需计分，词状态应为 relearning');
    expect(state.isReviewWord, true,
        reason: '重练期间仍属复习轨道,应标记为新词/旧词中的[旧词]');
    // 组进度异步刷新落定后再断言：仍停在测评环节，轨道名保持"旧词测评"
    await _waitUntil(container, (s) => s.groupStepTrackName != null);
    state = container.read(bdcNotifierProvider);
    expect(state.groupStepTrackName, '旧词测评',
        reason: '答错后仍留在测评环节，环节名不变');

    // 重练测评答对 → 才进入恢复环节(stepIndex=1)，环节名切换为"旧词答错"
    // 先受理这次作答（与线上判题链路一致），再提交流转
    notifier.acceptAnswerForTesting(FsrsRating.good);
    await notifier.getNextWord(true, fsrsRating: FsrsRating.good);
    state = container.read(bdcNotifierProvider);
    expect(state.currentGetWordResult!.stepIndex, 1,
        reason: '重练答对后才进入复习轨道恢复环节');
    expect(state.isReviewWord, true, reason: '恢复环节仍属复习轨道');
    await _waitUntil(container, (s) => s.groupStepTrackName == '旧词答错');
    state = container.read(bdcNotifierProvider);
    expect(state.groupStepTrackName, '旧词答错',
        reason: '恢复环节当前词轨道名为"旧词答错"');

    // 恢复环节答对 → 复习轨道今日完成，进入 List 环节（列表页）
    // 先受理这次作答（与线上判题链路一致），再提交流转
    notifier.acceptAnswerForTesting(FsrsRating.good);
    await notifier.getNextWord(true, fsrsRating: FsrsRating.good);
    state = container.read(bdcNotifierProvider);
    expect(state.loadError, '正在跳转到单词列表...',
        reason: '恢复环节答对后应进入列表页环节');

    await Future.delayed(const Duration(milliseconds: 100));
  });

  test('BdcNotifier - 本组进度指示：环节切换后的首个词给出顺序轻提示，点 × 关闭后不再出现', () async {
    // 本组轨道补全为 [En2Ch, Ch2En, List]，让环节切换真实发生
    for (final group in ['correct', 'wrong']) {
      await db.into(db.userStudySteps).insert(UserStudyStep(
            userId: testUser.id,
            scope: 'new',
            group: group,
            studyStep: 'Ch2En',
            seq: 0,
            state: 'Active',
            createTime: now,
            updateTime: now,
          ));
    }

    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    final keepAlive = container.listen(bdcNotifierProvider, (_, __) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    // 测评环节：本组仅 1 个词，进度 1/1；首次进入不提示
    await _waitUntil(container,
        (s) => s.groupStepPosition == 1 && s.groupStepTotal == 1);
    var state = container.read(bdcNotifierProvider);
    expect(state.studyStep, StudyStep.en2Ch.json);
    expect(state.groupStepHint, null, reason: '首次进入学习页不应弹出提示');
    expect(state.groupStepTrackName, '新词测评',
        reason: '测评环节尚未评分，当前词轨道名为"新词测评"');

    // 测评答对 → 本组进入汉译英环节：首词给出"整组推进"的顺序提示
    // 先受理这次作答（与线上判题链路一致），再提交流转
    notifier.acceptAnswerForTesting(FsrsRating.good);
    await notifier.getNextWord(true, fsrsRating: FsrsRating.good);
    await _waitUntil(container, (s) => s.groupStepHint != null);
    state = container.read(bdcNotifierProvider);
    expect(state.studyStep, StudyStep.ch2En.json);
    expect(state.groupStepPosition, 1);
    expect(state.groupStepTotal, 1);
    expect(state.groupStepNo, 1, reason: '本组仅 1 个词，仍是今日第 1 组');
    expect(state.groupStepTrackName, '新词答对',
        reason: '本组只有 1 个词且答对，轨道名为"新词答对"');

    expect(state.groupStepHint, isNot(null),
        reason: '环节切换后的首个词应提示"整组逐个推进到下一个环节"');

    // 点 × 关闭：立即收起当前这条，并把偏好落库（之后不再出现）
    await notifier.dismissGroupStepHint();
    state = container.read(bdcNotifierProvider);
    expect(state.groupStepHint, null, reason: '关闭后当前提示应立即收起');
    expect(StudyConfig.fromCurrentUser().hideGroupStepHint, true,
        reason: '关闭偏好应持久化');

    // 重新进入学习页（新 notifier 回到本环节首个词）：指示器仍在，但提示不再出现。
    // 新 notifier 的 groupStepPosition 只能由这次异步刷新人，故等待它就是等提示判定落定。
    final container2 = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    final keepAlive2 = container2.listen(bdcNotifierProvider, (_, __) {});
    await container2.read(bdcNotifierProvider.notifier).loadData(FakeBuildContext());
    await _waitUntil(container2,
        (s) => s.studyStep == StudyStep.ch2En.json && s.groupStepPosition == 1);
    state = container2.read(bdcNotifierProvider);
    expect(state.groupStepPosition, 1, reason: '指示器本身仍应展示');
    expect(state.groupStepHint, null, reason: '已关闭的提示不应再次出现');
    keepAlive2.close();
    container2.dispose();

    // 进入 List（本组小结）环节后指示与提示一并清空
    // 先受理这次作答（与线上判题链路一致），再提交流转
    notifier.acceptAnswerForTesting(FsrsRating.good);
    await notifier.getNextWord(true, fsrsRating: FsrsRating.good);
    state = container.read(bdcNotifierProvider);
    expect(state.groupStepPosition, 0);
    expect(state.groupStepTotal, 0);
    expect(state.groupStepHint, null);
  });

  test('BdcNotifier - Ch2En环节发音通过后残余低分ASR帧不应覆盖通关评分', () async {
    // 设置步骤配置为 Ch2En 测评
    await (db.delete(db.userStudySteps)..where((uss) => uss.userId.equals(testUser.id))).go();
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          scope: 'new',
          group: 'check',
          studyStep: 'Ch2En',
          seq: 0,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
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
    await notifier.loadData(FakeBuildContext());
    var state = container.read(bdcNotifierProvider);
    expect(state.studyStep, 'Ch2En');
    expect(state.hasFinishedAnswering, false);

    // 1. 用户发音精准命中单词 (word_1 的 spell 为 apple)
    await notifier.onAsrResult(jsonEncode({
      'best': 'apple',
      'candidates': ['apple'],
    }));

    state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, true, reason: '发音命中目标词应标记已答完');
    expect(state.currentScore, 100, reason: '精准匹配发音得分应为 100');

    // 2. 关麦过渡期间到达残余低分 ASR 帧（如尾音噪音识别为 banana）
    await notifier.onAsrResult(jsonEncode({
      'best': 'banana',
      'candidates': ['banana'],
    }));

    state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, true);
    expect(state.currentScore, 100, reason: '答完后收到的残余低分尾帧不应覆盖已取得的通关高分');

    // 3. 进入主动练习模式后（如清空或重练），重新发音应正常更新得分
    notifier.clearHint();
    state = container.read(bdcNotifierProvider);
    await notifier.onAsrResult(jsonEncode({
      'best': 'apple',
      'candidates': ['apply'],
    }));
    state = container.read(bdcNotifierProvider);
    expect(state.currentScore, isA<int>(), reason: '练习模式下应允许正常更新得分');

    await Future.delayed(const Duration(milliseconds: 100));
  });

  test('BdcNotifier - 前一个单词答对后快速点击下一词，自动跳转定时器应被取消，新词不应被误判答对', () async {
    final now = AppClock.now();
    // 额外插入第二个单词 word_2
    await db.into(db.words).insert(Word(
          id: 'word_2',
          spell: 'banana',
          popularity: 90,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.meaningItems).insert(MeaningItem(
          id: 'mim_2',
          wordId: 'word_2',
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
          wordId: 'word_2',
          seq: 2,
          unit: 0,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.learningWords).insert(LearningWord(
          userId: 'test_user_id',
          wordId: 'word_2',
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
        isExtra: false,
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
    await notifier.loadData(FakeBuildContext());
    var state = container.read(bdcNotifierProvider);
    expect(state.word!.spell, 'apple', reason: '初始应加载第一个词 apple');
    expect(state.hasFinishedAnswering, false);

    // 1. 回答正确第一个单词 (En2Ch: 说出中文 "苹果")
    await notifier.onAsrResult(jsonEncode({
      'best': '苹果',
      'candidates': ['苹果'],
    }));

    state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, true, reason: '第一个词答对后应标记为已答完');
    expect(state.canLeaveCurrWord, true, reason: '第一个词答对后允许点击下一词');

    // 2. 模拟用户在自动跳转（1000ms）触发前，快速点击【下一词】按钮
    await Future.delayed(const Duration(milliseconds: 50));
    final switchSuccess = await notifier.getNextWord(true, fsrsRating: state.lastFsrsRating);
    expect(switchSuccess, true, reason: '手动调用 getNextWord 应成功切词');

    state = container.read(bdcNotifierProvider);
    expect(state.word!.spell, 'banana', reason: '页面应成功切换到第二个词 banana');
    expect(state.hasFinishedAnswering, false, reason: '第二个词刚进入时绝不能是已答对状态');

    // 3. 等待足够时长，跨越原本 word_1 的 1000ms 自动跳转定时器
    await Future.delayed(const Duration(milliseconds: 1200));

    state = container.read(bdcNotifierProvider);
    expect(state.word!.spell, 'banana', reason: '定时器到期后不应跳过 banana，当前词仍必须是 banana');
    expect(state.hasFinishedAnswering, false, reason: 'banana 绝不能被上一词的幽灵定时器误判为答对');
  });

  test('BdcNotifier - 中文默写手写匹配成功后应回显释义（与语音说对一致）', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(bdcNotifierProvider.notifier);
    final context = FakeBuildContext();
    await notifier.loadData(context);

    // 打开中文默写
    notifier.openChineseDictation();
    var st = container.read(bdcNotifierProvider);
    expect(st.showHandwritingBoard, true);
    expect(st.isChineseDictation, true);

    // 手写识别出正确中文释义（"apple" -> "苹果"），与语音走同一套释义匹配+回显
    expect(st.asrPassRuleCache, 'ONE');
    await notifier.checkAsrResult(asrInput: '苹果', isVoice: false);

    st = container.read(bdcNotifierProvider);
    expect(st.hasFinishedAnswering, true, reason: '手写中文释义正确应标记为已答完');
    expect(st.showHandwritingBoard, false, reason: '答对后应退出全屏手写板回到主页面');
    expect(st.isChineseDictation, false, reason: '答对后应复位中文默写标记');

    final ww = st.wordWrapper!;
    // 用户写对的释义项应被标记为"已匹配"（绿色回显），这正是语音说对时的回显来源
    expect(ww.asrMatchedMeaningItemParts, isNotEmpty,
        reason: '用户手写写对的中文释义应被标记为已匹配，从而在主页面释义下划线处回显');
  });

  test('BdcNotifier - 中文默写一次性连续写出多个释义应全部回显并通过', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());
    container.read(bdcNotifierProvider).wordWrapper!.word.meaningItems = [
      MeaningItemVo.from('v.', '查看;考虑;观察'),
    ];
    // 通过线设为"全部释义都要答对"，从而检验连续写全时 3 个释义是否都算命中
    notifier.updateAsrPassRuleCache('ALL');

    notifier.openChineseDictation();
    var st = container.read(bdcNotifierProvider);
    // 进度门槛在开板时就按新释义预置：3 个释义全部答对才通过
    expect(st.dictationRequiredCount, 3);

    await notifier.checkAsrResult(asrInput: '查看考虑观察', isVoice: false);

    st = container.read(bdcNotifierProvider);
    expect(st.hasFinishedAnswering, true, reason: '一次连续写全释义应判通过');
    expect(st.showHandwritingBoard, false, reason: '通过后应退出手写板');
    expect(st.wordWrapper!.asrMatchedMeaningItemParts.length, 3,
        reason: '连续写出的三个释义都应被标记为已匹配并回显');
  });

  test('BdcNotifier - 单词已答对后再默写重写同一释义提交，应返回主页面且回显不变', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(bdcNotifierProvider.notifier);
    final context = FakeBuildContext();
    await notifier.loadData(context);

    // 第一次默写答对
    notifier.openChineseDictation();
    await notifier.checkAsrResult(asrInput: '苹果', isVoice: false);
    var st = container.read(bdcNotifierProvider);
    expect(st.hasFinishedAnswering, true);
    expect(st.showHandwritingBoard, false);
    expect(st.wordWrapper!.asrMatchedMeaningItemParts, isNotEmpty);
    final matchedBefore = List.of(st.wordWrapper!.asrMatchedMeaningItemParts);

    // 已答对后再次打开默写，把同一释义重写一遍并提交
    notifier.openChineseDictation();
    st = container.read(bdcNotifierProvider);
    expect(st.showHandwritingBoard, true);
    expect(st.isChineseDictation, true);

    await notifier.checkAsrResult(asrInput: '苹果', isVoice: false);
    st = container.read(bdcNotifierProvider);
    expect(st.hasFinishedAnswering, true, reason: '已答对状态应保持不变');
    expect(st.showHandwritingBoard, false, reason: '重写提交后应返回背单词主页面');
    expect(st.isChineseDictation, false, reason: '重写提交后应复位中文默写标记');
    // 释义回显不应变化
    expect(st.wordWrapper!.asrMatchedMeaningItemParts, matchedBefore,
        reason: '已回显的释义不应因再次默写而改变');

    // Note: 答错重写会走 ToastUtil.error 提示（保持手写板打开），
    // 但纯单元测试环境没有 ToastificationWrapper，无法实例化 toast，故此处不覆盖答错分支。
  });

  test('BdcNotifier - 中文默写只提交部分释义时发布进度且判题时机不变（需提交才判）', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    // 把当前词构造成 3 个释义子项，并把通过线设为"答对一半"（3 个需答对 2 个）
    container.read(bdcNotifierProvider).wordWrapper!.word.meaningItems = [
      MeaningItemVo.from('n.', '悲剧;灾难;惨案'),
    ];
    notifier.updateAsrPassRuleCache('HALF');

    // 打开默写：门槛已预置（写对 2 个才通过），尚未判题所以已答对为 0
    notifier.openChineseDictation();
    var st = container.read(bdcNotifierProvider);
    expect(st.dictationRequiredCount, 2, reason: '3 个子项按"答对一半"需答对 2 个');
    expect(st.dictationMatchedCount, 0);
    expect(st.hasFinishedAnswering, false, reason: '打开默写本身不判题');

    // 只写对一个释义后提交：未达通过线 → 手写板保持打开，进度前进到 1/2
    await notifier.checkAsrResult(asrInput: '悲剧', isVoice: false);
    st = container.read(bdcNotifierProvider);
    expect(st.hasFinishedAnswering, false);
    expect(st.showHandwritingBoard, true, reason: '未达通过线不应退出手写板');
    expect(st.dictationMatchedCount, 1, reason: '已答对 1 个释义');
    expect(st.dictationRequiredCount, 2, reason: '距通过还差 1 个释义');

    // 提交对不上任何释义时会走 ToastUtil.error（保持手写板打开），
    // 纯单元测试环境没有 ToastificationWrapper，无法覆盖该分支（详见上一个用例的说明）。

    // 再提交一个释义达到通过线 → 通过并退出手写板，进度复位
    await notifier.checkAsrResult(asrInput: '悲剧灾难', isVoice: false);
    st = container.read(bdcNotifierProvider);
    expect(st.hasFinishedAnswering, true);
    expect(st.showHandwritingBoard, false);
    expect(st.isChineseDictation, false);
    expect(st.dictationMatchedCount, 0, reason: '通过后复位进度');
    expect(st.dictationRequiredCount, 0, reason: '通过后复位进度');
  });

  test('BdcNotifier - 每次进入全屏拼写/默写界面时底部输入框保证为空白', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    // 模拟上一轮残留/恢复出来的作答文本
    notifier.updateMeaningTextWithoutCheck('残留文本');

    // 1. 英文拼写入口
    notifier.updateShowHandwritingBoard(true);
    expect(container.read(bdcNotifierProvider).showHandwritingBoard, true);
    expect(notifier.meaningController.text, '', reason: '进入拼写界面时输入框必须空白');

    // 界面内作答后退出，再次进入（重新进入也要空白）
    notifier.updateMeaningTextWithoutCheck('interim');
    notifier.updateShowHandwritingBoard(false);
    notifier.updateShowHandwritingBoard(true);
    expect(notifier.meaningController.text, '', reason: '重新进入拼写界面必须重新空白');

    // 2. 中文默写入口
    notifier.updateMeaningTextWithoutCheck('残留文本');
    notifier.openChineseDictation();
    final st = container.read(bdcNotifierProvider);
    expect(st.showHandwritingBoard, true);
    expect(st.isChineseDictation, true);
    expect(notifier.meaningController.text, '', reason: '进入默写界面时输入框必须空白');
  });

  test('BdcNotifier - 中文默写模式只属于打开中的手写板：关板/换模式后不得残留', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    // 换词是长异步流程：必须保持 provider 存活，否则中途会被 autoDispose 重建，
    // 后续读取到的就是全新 notifier 而不是被测实例
    final keepAlive = container.listen(bdcNotifierProvider, (_, __) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    // 1. 中文默写开着时，模式有效
    notifier.openChineseDictation();
    var st = container.read(bdcNotifierProvider);
    expect(st.showHandwritingBoard, true);
    expect(st.isChineseDictation, true);

    // 2. 板子被关闭（答对过渡/取消等任意关板路径的统一点）→ 模式与进度一并复位
    notifier.updateShowHandwritingBoard(false);
    st = container.read(bdcNotifierProvider);
    expect(st.showHandwritingBoard, false);
    expect(st.isChineseDictation, false,
        reason: '手写板关闭后绝不能残留中文默写标记（否则背单词页会按默写严格判错并刷提示）');
    expect(st.dictationMatchedCount, 0);
    expect(st.dictationRequiredCount, 0);

    // 3. 先默写再开「拼写」入口：拼写板必须是拼写模式，不能继承中文默写模式
    notifier.openChineseDictation();
    notifier.updateShowHandwritingBoard(true);
    st = container.read(bdcNotifierProvider);
    expect(st.showHandwritingBoard, true);
    expect(st.isChineseDictation, false, reason: '「拼写」入口打开的必须是英文拼写板');
    expect(st.dictationRequiredCount, 0, reason: '拼写板不应带默写通过门槛');
  });

  test('BdcState - 关闭手写板时中文默写模式与进度必须一并复位', () {
    const dictating = BdcState(
      showHandwritingBoard: true,
      isChineseDictation: true,
      dictationMatchedCount: 2,
      dictationRequiredCount: 3,
    );

    // 关板（答对过渡/取消/换词等所有关板路径的统一点）→ 模式与进度必须一并复位
    final closed = dictating.copyWith(showHandwritingBoard: false);
    expect(closed.isChineseDictation, false,
        reason: '残留的默写标记会让背单词页的正常作答被按默写严格判错并刷提示');
    expect(closed.dictationMatchedCount, 0);
    expect(closed.dictationRequiredCount, 0);

    // 板子仍打开时模式保持不变（不误伤正常默写）
    expect(dictating.copyWith(tabIndex: 1).isChineseDictation, true);
    expect(dictating.copyWith(tabIndex: 1).dictationRequiredCount, 3);
  });

  test('BdcNotifier - 进入中文默写会取消挂起的 AI 裁判，当前词不会被换走', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    // 本用例含 1.5s 以上的真实等待：必须持有监听，避免 autoDispose 在等待期间销毁 notifier
    final keepAlive = container.listen(bdcNotifierProvider, (_, __) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });

    // 用可控的 Completer 替代真实大模型调用，模拟"裁判请求仍在途"
    final judgeCompleter = Completer<Result<String>>();
    AiRefereeUtil.aiChatOverride = (messagesJson, userId) => judgeCompleter.future;
    addTearDown(() => AiRefereeUtil.aiChatOverride = null);

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    container.read(bdcNotifierProvider).wordWrapper!.word.meaningItems = [
      MeaningItemVo.from('a.', '竞争的;竞争激烈的;好胜的'),
    ];
    notifier.updateAsrPassRuleCache('HALF');
    final spellBefore = container.read(bdcNotifierProvider).word!.spell;

    // 说了一句本地完全识别不出的回答 → 挂起 1.5s 防抖的 AI 裁判兜底
    await notifier.onAsrResult(jsonEncode({
      'best': '苹果香蕉',
      'candidates': ['苹果香蕉'],
      'isFinal': true,
    }));
    expect(notifier.hasPendingWordAiReferee, true, reason: '本地一个都没命中，应调度 AI 裁判兜底');

    // 用户在裁判返回前打开默写：挂起的裁判必须被取消。
    // 否则裁判一旦认可就把当前词换走，用户正写着的默写板被强行关闭、模式标记残留。
    notifier.openChineseDictation();
    expect(notifier.hasPendingWordAiReferee, false,
        reason: '进入默写应取消挂起的 AI 裁判兜底，避免默写期间词被换走');

    await Future.delayed(const Duration(milliseconds: 1700));
    final st = container.read(bdcNotifierProvider);
    expect(st.showHandwritingBoard, true, reason: '默写板应保持打开');
    expect(st.isChineseDictation, true);
    expect(st.word!.spell, spellBefore, reason: '当前词不得在默写期间被换走');
  });

  test('BdcNotifier - 关闭默写板后，背单词页的语音判题不再走中文默写分支', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    container.read(bdcNotifierProvider).wordWrapper!.word.meaningItems = [
      MeaningItemVo.from('a.', '苹果;香蕉;橘子'),
    ];
    notifier.updateAsrPassRuleCache('HALF');

    // 默写板打开后又被关闭（不经成功路径）
    notifier.openChineseDictation();
    notifier.updateShowHandwritingBoard(false);

    // 回到背单词页说话：本地一个释义都没识别出的回答应回落 AI 裁判兜底（正常链路）。
    // 若残留了中文默写标记，判题会走默写分支并在判错处直接 return，
    // 既不调度 AI 裁判、也不推进答题——正是用户反馈的"页面就停止了"。
    await notifier.onAsrResult(jsonEncode({
      'best': '完全对不上的答案',
      'candidates': ['完全对不上的答案'],
      'isFinal': true,
    }));
    expect(notifier.hasPendingWordAiReferee, true,
        reason: '关板后应回到正常语音判题链路（可回落 AI 裁判），而不是中文默写分支');
  });

  test('英译汉环节例句释义遮盖状态控制与评分判定', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    // 1. 验证默认初始化状态
    expect(container.read(bdcNotifierProvider).showSentenceWordMeaning, isFalse);

    // 2. 验证 toggle 与 update
    notifier.toggleShowSentenceWordMeaning();
    expect(container.read(bdcNotifierProvider).showSentenceWordMeaning, isTrue);

    notifier.updateShowSentenceWordMeaning(false);
    expect(container.read(bdcNotifierProvider).showSentenceWordMeaning, isFalse);

    // 3. 验证 hideAnswer 重置 showSentenceWordMeaning
    notifier.revealAnswerAndMarkWrong(FakeBuildContext());
    notifier.updateShowSentenceWordMeaning(true);
    notifier.hideAnswer();
    expect(container.read(bdcNotifierProvider).showSentenceWordMeaning, isFalse);
  });
  // ===== 回归护栏：同一次作答被多条链路重复提交，只能计一次分，且不得吞掉下一个学习环节 =====

  test('BdcNotifier - 重复提交同一作答只计一次分且不吞掉下一个环节', () async {
    // 线上活跃用户配置：新词答对组 = [Ch2En]（第二个评分环节）
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          scope: 'new',
          group: 'correct',
          studyStep: 'Ch2En',
          seq: 0,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    // 真实作答：中文默写识别答对（受理一次作答）
    notifier.openChineseDictation();
    await notifier.checkAsrResult(asrInput: '苹果', isVoice: false);
    final rating = container.read(bdcNotifierProvider).lastFsrsRating;
    expect(rating, isA<FsrsRating>(), reason: '答对后应有评分');

    // 同一次作答被两条链路各触发一次流转（autoJump 定时器 + 下一词按钮）
    await notifier.getNextWord(true, fsrsRating: rating);
    await notifier.getNextWord(true, fsrsRating: rating);
    await Future.delayed(const Duration(milliseconds: 200));

    final logs = await db.learningLogsDao.getHistory(testUser.id, 'word_1');
    expect(logs.length, 1,
        reason: '同一次作答被重复提交只应写一条评分日志，实际 ${logs.length} 条');

    final w = await (db.select(db.learningWords)..where((t) => t.wordId.equals('word_1'))).getSingle();
    expect(w.todayLearnedTimes, 1,
        reason: '第二个学习环节不应被重复提交顶掉（todayLearnedTimes 应为 1）');
  });

  test('BdcNotifier - 手写板打开期间再次判题不得二次受理同一次作答', () async {
    final mockAsr = MockAsr();
    final container = ProviderContainer(
      overrides: [asrProvider.overrideWithValue(mockAsr)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    // 先"看答案"（受理一次 again），再打开手写板重复判题：
    // 旧实现在手写板打开时会跳过守卫，从而把这次作答二次受理成 easy
    notifier.revealAnswerAndMarkWrong(FakeBuildContext());
    notifier.openChineseDictation();
    await notifier.checkAsrResult(asrInput: '苹果', isVoice: false);
    expect(container.read(bdcNotifierProvider).lastFsrsRating, FsrsRating.again,
        reason: '已受理的作答不得被第二次判题覆盖成其它评分');

    await notifier.getNextWord(true, fsrsRating: FsrsRating.again);
    await Future.delayed(const Duration(milliseconds: 200));

    final logs = await db.learningLogsDao.getHistory(testUser.id, 'word_1');
    expect(logs.length, 1, reason: '一次呈现只应产生一条评分日志');
    expect(logs.first.rating, FsrsRating.again.value,
        reason: '落库评分应是受理时的 again，而不是后来判题算出的 easy');
  });

  // ===== 无评分的"作答后流转"不得推进环节计数（无凭据即丢弃） =====
  test('BdcNotifier - 无评分的作答后流转必须丢弃：不得推进今日环节计数', () async {
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
    await notifier.loadData(FakeBuildContext());
    expect(container.read(bdcNotifierProvider).word!.spell, 'apple');

    // 答案已揭晓（作答后），但没有任何"已受理凭据"：例如练习模式只揭晓答案、
    // 或凭据已被丢弃后 UI 状态残留。此时若继续流转，StudyBo 会把 fsrsRating == null
    // 当成正常推进（advanceStep = 评分 != again 对 null 为 true），
    // 于是环节被跳过、今日进度虚高，却既没有学习记录也没有 FSRS 更新。
    notifier.updateHasFinishedAnswering(true);

    await notifier.getNextWord(true);

    final lw = await (db.select(db.learningWords)
          ..where((t) =>
              t.userId.equals(testUser.id) & t.wordId.equals('word_1')))
        .getSingle();
    expect(lw.todayLearnedTimes, 0, reason: '不得推进今日学习环节计数');
    expect(lw.learnedTimes, 0, reason: '不得推进累计学习次数');
    final logs = await db.learningLogsDao.getHistory(testUser.id, 'word_1');
    expect(logs, isEmpty, reason: '无评分流转不得凭空推进进度，也不该留下学习记录');
    expect(container.read(bdcNotifierProvider).word!.spell, 'apple',
        reason: '当前词不得被换走');

    await Future.delayed(const Duration(milliseconds: 50));
  });

  // ===== 练习模式（看答案 → 隐藏答案 → 练习答对）不得把「下一词」锁死 =====
  test('BdcNotifier - 练习模式：看答案→隐藏答案→练习答对后「下一词」仍能正常流转', () async {
    // 例句环节 setup：轨道 [En2Ch, EnSentence2Ch, List]，stepIndex=1 即例句环节
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          scope: 'new',
          group: 'correct',
          studyStep: 'EnSentence2Ch',
          seq: 0,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(todayLearnedTimes: const Value(1)));
    // 今天首条评分日志（elapsedDays=0, good）：轨道按答对组扩展
    await db.learningLogsDao.saveEntity(LearningLog(
          id: 'first_log_word_1',
          userId: testUser.id,
          wordId: 'word_1',
          rating: FsrsRating.good.value,
          stability: 2.4,
          difficulty: 3.05,
          elapsedDays: 0,
          scheduledDays: 2,
          createTime: now,
          updateTime: now,
        ), false);
    await db.into(db.sentences).insert(Sentence(
          id: 'snt_practice',
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

    // 1. 看答案：受理一条 again 凭据，今日测评就此定案
    notifier.revealAnswerAndMarkWrong(context);
    var state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, true);
    expect(state.lastFsrsRating, FsrsRating.again);

    // 2. 隐藏答案继续练习
    notifier.hideAnswer();
    state = container.read(bdcNotifierProvider);
    expect(state.isPracticeMode, true);
    expect(state.hasFinishedAnswering, false);

    // 3. 练习答对：只反馈、只揭晓答案，不登记新凭据、不改今日评分
    notifier.startPttAsr();
    for (var i = 0; i < 20 && mockAsr.startAsrCallCount < 1; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    await notifier.onAsrResult(jsonEncode({
      'best': '我每天早上吃一个苹果',
      'candidates': ['我每天早上吃一个苹果'],
      'isFinal': true,
    }));
    await notifier.stopPttAsr();
    await Future.delayed(const Duration(milliseconds: 100));
    state = container.read(bdcNotifierProvider);
    expect(state.hasFinishedAnswering, true, reason: '练习答对也要揭晓答案，用户才能比对');
    expect(state.lastFsrsRating, FsrsRating.again, reason: '练习答对不得改写今日评分');

    // 4. 「下一词」：必须凭"看答案"那次已受理的 again 凭据真正流转。
    //    旧实现 hideAnswer 把待计分凭据清空，这里会被判成"重复/迟到提交"直接丢弃，
    //    表现为按钮点了没反应（既不换词也不落评分）。
    final advanced =
        await notifier.getNextWord(true, fsrsRating: state.lastFsrsRating);
    await Future.delayed(const Duration(milliseconds: 200));
    expect(advanced, true, reason: '练习模式离开必须能流转，不得静默丢弃');

    final logs = await db.learningLogsDao.getHistory(testUser.id, 'word_1');
    expect(logs.length, 2, reason: '看答案的 again 必须在离开时落一条学习记录');
    expect(logs.first.rating, FsrsRating.again.value,
        reason: '落库评分应是看答案时的 again，而不是练习后的得分');

    await Future.delayed(const Duration(milliseconds: 50));
  });

  // ===== 流转失败不得吞掉已受理凭据（否则当前词被永久锁死） =====
  test('BdcNotifier - 取词失败后凭据保留：原样重试「下一词」仍能计分', () async {
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
    await notifier.loadData(FakeBuildContext());

    // 受理一次作答（good）
    notifier.acceptAnswerForTesting(FsrsRating.good);

    // 让这次流转失败：未登录时 StudyBo.getWord 直接返回失败
    // （失败分支会弹提示条，纯单元测试没有 ToastificationWrapper，故接住该断言错误）
    await Prefs.remove('currentUserId');
    await Global.loadUserFromDb();
    await _ignoreToastUnavailable(
        () => notifier.getNextWord(true, fsrsRating: FsrsRating.good));

    // 失败后凭据必须还在：用户恢复登录后原样重试「下一词」要能真正计分。
    // 旧实现先清凭据再取词，失败后 _answerAccepted 仍为真、凭据却已为空，
    // 于是之后所有「下一词 / 不认识 / 再学学」都被判成"重复/迟到提交"而静默失效。
    Global.updateUserCache(testUser);
    await notifier.getNextWord(true, fsrsRating: FsrsRating.good);

    final logs = await db.learningLogsDao.getHistory(testUser.id, 'word_1');
    expect(logs.length, 1, reason: '重试成功后才落库，且只落一条评分日志');
    expect(logs.first.rating, FsrsRating.good.value);

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('BdcNotifier - 取词失败后改用别的评分（再学学）仍能受理', () async {
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
    await notifier.loadData(FakeBuildContext());

    notifier.acceptAnswerForTesting(FsrsRating.good);
    await Prefs.remove('currentUserId');
    await Global.loadUserFromDb();
    await _ignoreToastUnavailable(
        () => notifier.getNextWord(true, fsrsRating: FsrsRating.good));

    // 用户改主意点「再学学」（again）：失败分支必须复位"已受理"标记，
    // 否则 _acceptAnswer 会把它当成同一呈现的重复受理而直接忽略。
    Global.updateUserCache(testUser);
    notifier.acceptAnswerForTesting(FsrsRating.again);
    await notifier.getNextWord(true, fsrsRating: FsrsRating.again);

    final logs = await db.learningLogsDao.getHistory(testUser.id, 'word_1');
    expect(logs.length, 1, reason: '新意图应登记成新凭据并落库一条日志');
    expect(logs.first.rating, FsrsRating.again.value,
        reason: '落库评分应是用户最后选定的 again');

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('BdcNotifier - 修改今日评分:业务日窗口内的「昨天23:50测评+今天01:00巩固」必须同属一天', () async {
    // 改评分发生在 6/16 01:30 → 业务日 6/15，窗口 [6/15 03:00, 6/16 03:00)。
    // 「6/15 23:50 测评」与「6/16 01:00 巩固」都落在窗口内，是同一个业务日的两条日志；
    // 6/15 02:00 那条属前一业务日 6/14，只能当重放基准，绝不能被当成"当天首条日志"替换。
    AppClock.setClock(FakeClock(DateTime(2026, 6, 16, 1, 30)));
    addTearDown(AppClock.reset);

    final baselineTime = DateTime(2026, 6, 15, 2, 0); // 业务日 6/14
    final assessTime = DateTime(2026, 6, 15, 23, 50); // 业务日 6/15 首条
    final consolidateTime = DateTime(2026, 6, 16, 1, 0); // 业务日 6/15 第二条

    // 用户与当前词都归到业务日 6/15
    final bdUser = testUser.copyWith(
      lastLearningDate: Value(DateTime(2026, 6, 15)),
      todayStudyStarted: true,
    );
    await db.usersDao.saveUser(bdUser, false);
    Global.updateUserCache(bdUser);
    testUser = bdUser;

    await (db.update(db.learningWords)
          ..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(
      stability: const Value(35.21175712420889),
      difficulty: const Value(2.135155608561961),
      reps: const Value(2),
      lapses: const Value(0),
      scheduledDays: const Value(35),
      state: const Value(2), // Review
      addTime: Value(DateTime(2026, 6, 14)),
      addDay: const Value(1),
      isTodayNewWord: const Value(false),
      lastLearningDate: Value(DateTime(2026, 6, 14)),
      learnedTimes: const Value(3),
      todayLearnedTimes: const Value(0),
    ));

    // 重放基准 = 前一业务日的最后一条
    await db.learningLogsDao.saveEntity(
        LearningLog(
          id: 'log_bd_baseline',
          userId: testUser.id,
          wordId: 'word_1',
          rating: FsrsRating.easy.value,
          stability: 15.69105,
          difficulty: 3.2245015893713678,
          elapsedDays: 5,
          scheduledDays: 16,
          createTime: baselineTime,
          updateTime: baselineTime,
        ),
        false);
    // 当天首条 = 6/15 23:50 测评
    await db.learningLogsDao.saveEntity(
        LearningLog(
          id: 'log_bd_assess',
          userId: testUser.id,
          wordId: 'word_1',
          rating: FsrsRating.easy.value,
          stability: 25.012414485811277,
          difficulty: 2.1301214599670124,
          elapsedDays: 1,
          scheduledDays: 25,
          createTime: assessTime,
          updateTime: assessTime,
        ),
        false);
    // 当天第二条 = 6/16 01:00 巩固
    await db.learningLogsDao.saveEntity(
        LearningLog(
          id: 'log_bd_consolidate',
          userId: testUser.id,
          wordId: 'word_1',
          rating: FsrsRating.good.value,
          stability: 35.21175712420889,
          difficulty: 2.135155608561961,
          elapsedDays: 0,
          scheduledDays: 35,
          createTime: consolidateTime,
          updateTime: consolidateTime,
        ),
        false);
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
    await notifier.loadData(FakeBuildContext());
    expect(container.read(bdcNotifierProvider).word!.spell, 'apple');

    Future<LearningLog> logById(String id) async {
      final logs = await db.learningLogsDao.getHistory(testUser.id, 'word_1');
      return logs.firstWhere((l) => l.id == id);
    }

    // 把「当天首条」改成 good
    notifier.updateFsrsRating(FsrsRating.good);
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      if ((await logById('log_bd_assess')).rating == FsrsRating.good.value) break;
    }

    final baselineLog = await logById('log_bd_baseline');
    final assessLog = await logById('log_bd_assess');
    final consolidateLog = await logById('log_bd_consolidate');

    expect(baselineLog.rating, FsrsRating.easy.value,
        reason: '前一业务日的日志只能当重放基准，不得被当成"当天首条"替换');
    expect(baselineLog.stability, 15.69105);
    expect(baselineLog.scheduledDays, 16);
    expect(consolidateLog.rating, FsrsRating.good.value,
        reason: '巩固日志必须保持原评分，不得被新评分污染');
    expect(consolidateLog.stability, closeTo(35.21175712420889, 1e-9));

    // 首条日志只写"重放首步态"：next(基准, good, 1)，跨天间隔 1 天必须保留
    final fsrs = FSRS();
    final baseItem = FSRSItem(
      stability: 15.69105,
      difficulty: 3.2245015893713678,
      elapsedDays: 0,
      scheduledDays: 16,
      reps: 0,
      lapses: 0,
      state: FsrsState.review,
    );
    final expectedFirstStep = fsrs.next(baseItem, FsrsRating.good, 1);
    final expectedReplayed = fsrs.next(expectedFirstStep, FsrsRating.good, 0);

    expect(assessLog.elapsedDays, 1,
        reason: '若把 6/15 02:00 那条误当"当天首条"，这里会变成它的间隔 5 天');
    expect(assessLog.stability, closeTo(expectedFirstStep.stability, 1e-9));
    expect(assessLog.scheduledDays, expectedFirstStep.scheduledDays);

    final lw = await (db.select(db.learningWords)
          ..where((t) =>
              t.userId.equals(testUser.id) & t.wordId.equals('word_1')))
        .getSingle();
    expect(lw.stability, closeTo(expectedReplayed.stability, 1e-9),
        reason: 'learning_words 写重放末态：首条 good + 巩固 good');
    expect(lw.scheduledDays, expectedReplayed.scheduledDays);
    expect(lw.reps, expectedReplayed.reps);
    expect(lw.todayLearnedTimes, 0, reason: '修改评分不得改动今日环节次数');
    expect(lw.learnedTimes, 3);
    expect((await db.learningLogsDao.getHistory(testUser.id, 'word_1')).length, 3,
        reason: '只允许原地替换当天首条日志');

    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('今天最近一次答错的词：呈现时标记为"最近答错"，答对后立刻撤掉', () async {
    // 今天两条评分：先 good、后 again —— 最近一次是答错
    final now2 = AppClock.now();
    await db.learningLogsDao.saveEntity(
      LearningLog(
        id: 'log_first_good',
        userId: testUser.id,
        wordId: 'word_1',
        rating: FsrsRating.good.value,
        stability: 2.4,
        difficulty: 3.05,
        elapsedDays: 0,
        scheduledDays: 2,
        createTime: now2.subtract(const Duration(minutes: 5)),
        updateTime: now2.subtract(const Duration(minutes: 5)),
      ),
      false,
    );
    await db.learningLogsDao.saveEntity(
      LearningLog(
        id: 'log_latest_again',
        userId: testUser.id,
        wordId: 'word_1',
        rating: FsrsRating.again.value,
        stability: 0.4,
        difficulty: 3.05,
        elapsedDays: 0,
        scheduledDays: 1,
        createTime: now2,
        updateTime: now2,
      ),
      false,
    );
    StudyCacheManager().clear();

    final mockAsr = MockAsr();
    final container = ProviderContainer(overrides: [
      asrProvider.overrideWithValue(mockAsr),
    ]);
    final keepAlive = container.listen(bdcNotifierProvider, (_, __) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    var state = container.read(bdcNotifierProvider);
    expect(state.word!.id, 'word_1');
    expect(state.isLatestAnswerWrongToday, isTrue,
        reason: '今天最近一次评分是 again，拼写应标红');

    // 这次答对：红色提示应立即撤掉
    notifier.acceptAnswerForTesting(FsrsRating.good);
    await notifier.getNextWord(true, fsrsRating: FsrsRating.good);

    state = container.read(bdcNotifierProvider);
    expect(state.isLatestAnswerWrongToday, isFalse,
        reason: '本词已答对，或已换到别的词，红色提示都必须消失');

    await Future.delayed(const Duration(milliseconds: 50));
  });
}
