// ignore_for_file: avoid_print

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:flutter/services.dart';
import 'package:nnbdc/util/learning_service.dart';

// 手写 MockAsr，捕获并拦截所有的原生方法
class MockAsr implements Asr {
  final AsrState _state = AsrState.initialized;
  final List<Function(AsrState)> _stateListeners = [];

  @override
  AsrState get state => _state;

  @override
  bool get isPreloaded => true;

  @override
  bool get permissionGranted => true;

  @override
  set permissionGranted(bool value) {}

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
  Future<void> startAsr(AsrLanguage language, {List<String>? phrases, bool playHintSound = true}) async {}

  @override
  Future<String?> stopAsr() async => null;

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
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  late StudyBo studyBo;
  late FakeClock fakeClock;

  setUpAll(() {
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        return {};
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  setUp(() async {
    StudyAudioSessionController.instance.audioSessionConfigured = true;
    
    // 初始化 Fake 虚拟时钟为 Day 1: 2026-05-20 08:00:00
    fakeClock = FakeClock(DateTime(2026, 5, 20, 8, 0, 0));
    AppClock.setClock(fakeClock);

    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    studyBo = StudyBo();
    StudyCacheManager().clear();

    final now = AppClock.now();

    // 1. 创建 Mock User，计划每日学 3 个单词
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
      wordsPerDay: 3,
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

    // 2. 生成学习步骤配置: En2Ch（英译汉） + List（浏览）两个主要步骤
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'En2Ch',
          seq: 0,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'List',
          seq: 1,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));

    // 3. 生成用户的“已掌握”和“生词本”词书，因为 StudyBo 和 MasteredWordsDao 极其依赖它们
    var masteredDictId = 'mock_dict_mastered';
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

    var rawDictId = 'mock_dict_raw';
    await db.into(db.dicts).insert(Dict(
          id: rawDictId,
          name: '生词本',
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

    // 4. 生成包含 8 个单词的 Mock 词书供日常抓取学习
    var dictId = 'mock_integration_dict';
    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '整书仿真词汇',
          wordCount: 8,
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

    // 8个测试单词 spell
    final List<String> wordSpells = [
      'apple',
      'banana',
      'cherry',
      'date',
      'elderberry',
      'fig',
      'grape',
      'honeydew'
    ];

    for (int i = 0; i < wordSpells.length; i++) {
      final wordId = 'w_${i + 1}';
      final spell = wordSpells[i];
      
      await db.into(db.words).insert(Word(
            id: wordId,
            spell: spell,
            popularity: 100,
            createTime: now,
            updateTime: now,
          ));

      await db.into(db.meaningItems).insert(MeaningItem(
            id: 'mim_${i + 1}',
            wordId: wordId,
            dictId: Global.commonDictId,
            ciXing: 'n.',
            meaning: '$spell的含义',
            popularity: 100,
            ownerId: Global.sysUserId,
            createTime: now,
            updateTime: now,
          ));

      await db.into(db.dictWords).insert(DictWord(
            dictId: dictId,
            wordId: wordId,
            seq: i + 1,
            unit: 0,
            createTime: now,
            updateTime: now,
          ));
    }
  });

  tearDown(() async {
    await db.close();
    AppClock.reset();
  });

  test('多天端到端全词书学习流集成测试', () async {
    final mockAsr = MockAsr();

    final container = ProviderContainer(
      overrides: [
        asrProvider.overrideWithValue(mockAsr),
      ],
    );
    addTearDown(container.dispose);

    // ============================================
    // DAY 1: 首次背词仿真 (学习计划: 3新词)
    // ============================================
    print('[Day 1] 🚀 开始第一天的真实新词抓取...');
    
    // 1. 准备今日学习单词，抓取 3 个新词
    var prepResult = await LearningService.prepareTodayStudy(true);
    expect(prepResult.success, true);
    expect(prepResult.data![0], 3); // 抓取了 3 个新词
    expect(prepResult.data![1], 0); // 0 个复习词

    // 检查今日单词列表，对应 w_1 (apple), w_2 (banana), w_3 (cherry)
    var todayWords = await StudyCacheManager().getTodayWords(db, testUser.id);
    expect(todayWords.length, 3);
    expect(todayWords[0].wordId, 'w_1');
    expect(todayWords[1].wordId, 'w_2');
    expect(todayWords[2].wordId, 'w_3');

    // 2. 模拟精细化答题操作
    // 获取第一个单词：w_1 (apple)
    var getWordRes = await studyBo.getWord(false, false);
    expect(getWordRes.success, true);
    var wordVo = getWordRes.data!.learningWord;
    expect(wordVo!.word.id, 'w_1');
    expect(getWordRes.data!.stepIndex, 0); // 当前是步骤 0 (En2Ch)

    // 模拟 w_1 回答正确 (Good)，进入 FSRS 评分保存
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);

    // 获取第二个单词：w_2 (banana)
    getWordRes = await studyBo.getWord(false, false);
    wordVo = getWordRes.data!.learningWord;
    expect(wordVo!.word.id, 'w_2');

    // 模拟 w_2 答错 (Again)。应该会自动触发记录错词本
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
    
    // 断言：错词本里确实多了一条 w_2 错词记录
    final wrongWord = await db.userWrongWordsDao.getEntity(testUser.id, 'w_2');
    expect(wrongWord != null, true);

    // 获取第三个单词：w_3 (cherry)
    getWordRes = await studyBo.getWord(false, false);
    wordVo = getWordRes.data!.learningWord;
    expect(wordVo!.word.id, 'w_3');

    // 模拟用户对 w_3 点击“完全掌握”。w_3 应该直接毕业进入已掌握词表
    await studyBo.getWord(true, true); // isWordMastered = true

    // 断言：w_3 已被记录在已掌握表
    final isW3Mastered = await db.masteredWordsDao.isWordMastered(testUser.id, 'w_3');
    expect(isW3Mastered, true);

    // 此时第一批次的所有词均已完成 En2Ch(步骤0)，下一步应该自动进入 List(步骤1)
    getWordRes = await studyBo.getWord(false, false);
    expect(getWordRes.data!.learningWord, isNotNull);
    expect(getWordRes.data!.learningWord!.batchId, isNotNull);
    expect(getWordRes.data!.stepIndex, 1); // 步骤 1: List

    // 3. 完成批量列表浏览 (completeListStepForCurrentBatch)
    var completeListRes = await studyBo.completeListStepForCurrentBatch();
    expect(completeListRes.success, true);

    // 4. 再次获取单词，应该触发今日学习圆满完成 (finished = true)
    getWordRes = await studyBo.getWord(false, false);
    expect(getWordRes.data!.finished, true);

    // 5. 模拟打卡结算与掷骰子
    var dakaRes = await studyBo.saveDakaRecord("打卡心情：第一天轻松通过！");
    expect(dakaRes.success, true);

    // 强制同步内存缓存，以获取打卡后赠送的掷骰子机会
    final latestUser = await db.usersDao.getUserById(testUser.id);
    Global.updateUserCache(latestUser!);

    var diceRes = await studyBo.throwDiceAndSave();
    expect(diceRes.success, true);
    expect(diceRes.data! >= 1 && diceRes.data! <= 5, true); // 骰子魔法泡泡增加为 1~5

    // 断言第一天结算状态
    var userInDb = await db.usersDao.getUserById(testUser.id);
    expect(userInDb!.dakaDayCount, 1);
    expect(userInDb.continuousDakaDayCount, 1);
    expect(userInDb.cowDung > 0, true); // 魔法泡泡已经增加

    // ============================================
    // DAY 2: 时间旅行到第二天 (学习计划: 复习旧词 + 补足新词)
    // ============================================
    print('\n[Day 2] ✈️ 跨天时间旅行推进至第二天...');
    
    // 推进 Fake 时钟一天 (24 小时)
    fakeClock.advanceDays(1);
    
    // 强制触发更新最后的活跃缓存与今日业务日期重置
    userInDb = await db.usersDao.getUserById(testUser.id);
    // 重设 lastLearningDate 开启全新一天
    final day2User = userInDb!.copyWith(todayStudyStarted: false);
    await db.usersDao.saveUser(day2User, true);
    Global.updateUserCache(day2User);

    // 重新准备今日学习单词
    prepResult = await LearningService.prepareTodayStudy(true);
    expect(prepResult.success, true);
    
    // 由于 w_1 (Good) 第一天稳定性为 2.40，到期时间 2 天，所以第二天未到期；
    // w_2 (Again) 第一天稳定性为 0.40，到期时间 1 天，所以第二天到期复习；
    // w_3 已经完全掌握（毕业），不再抓取。
    // 为了补足每日的 3 个词计划，系统会额外抓取 2 个新词（w_4, w_5）。
    // 断言抓取结构：2 个新词，1 个复习词
    expect(prepResult.data![0], 2); // 2 个新词 (w_4, w_5)
    expect(prepResult.data![1], 1); // 1 个复习词 (w_2)

    todayWords = await StudyCacheManager().getTodayWords(db, testUser.id);
    expect(todayWords.length, 3);
    
    // 验证确实是 w_2, w_4, w_5
    final wordIds = todayWords.map((w) => w.wordId).toSet();
    print('DEBUG: Day 2 wordIds = $wordIds');
    expect(wordIds.contains('w_2'), true);
    expect(wordIds.contains('w_4'), true);
    expect(wordIds.contains('w_5'), true);
    expect(wordIds.contains('w_1'), false); // 未到期
    expect(wordIds.contains('w_3'), false); // 已毕业

    // 模拟第二天的精细学习：w_2, w_4, w_5 在 En2Ch 均回答 Good
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.good); // 批次中首词回答 Good
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.good); // 次词回答 Good
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.good); // 末词回答 Good
    
    // 批次完成 En2Ch，应自动进入 List 步骤 (stepIndex == 1)
    getWordRes = await studyBo.getWord(false, false);
    expect(getWordRes.data!.learningWord, isNotNull);
    expect(getWordRes.data!.learningWord!.batchId, isNotNull);
    expect(getWordRes.data!.stepIndex, 1);

    await studyBo.completeListStepForCurrentBatch();
    
    // 再次获取应判定今日学完
    getWordRes = await studyBo.getWord(false, false);
    expect(getWordRes.data!.finished, true);

    // 进行第二天打卡
    dakaRes = await studyBo.saveDakaRecord("打卡心情：第二天也坚持了！");
    expect(dakaRes.success, true);

    userInDb = await db.usersDao.getUserById(testUser.id);
    expect(userInDb!.dakaDayCount, 2);
    expect(userInDb.continuousDakaDayCount, 2); // 连续打卡累计为 2 天！

    // ============================================
    // DAY 3 至 DAY N: 连续推进直至全书所有单词毕业
    // ============================================
    print('\n[Day 3+] 🔄 持续推进时间，仿真每日全书学习，直到最终毕业...');
    
    int loopCount = 0;
    while (loopCount < 20) { // 最多运行 20 虚拟天，保证测试不陷入无限循环
      loopCount++;
      fakeClock.advanceDays(1);

      userInDb = await db.usersDao.getUserById(testUser.id);
      final loopUser = userInDb!.copyWith(todayStudyStarted: false);
      await db.usersDao.saveUser(loopUser, true);
      Global.updateUserCache(loopUser);

      prepResult = await LearningService.prepareTodayStudy(true);
      final allMastered = await db.masteredWordsDao.getMasteredWordsForUser(testUser.id);
      if (allMastered.length == 8) {
        print('🎉 仿真在第 ${loopCount + 2} 天时检测到全书 8 个词全部毕业！');
        break;
      }

      todayWords = await StudyCacheManager().getTodayWords(db, testUser.id);
      if (todayWords.isEmpty) {
        print('⏳ 第 ${loopCount + 2} 天无词到期，直接跳过并打卡，进入下一天...');
        await studyBo.saveDakaRecord("第 ${loopCount + 2} 天休息打卡！");
        continue;
      }

      // 用通用状态机答题流进行今日学习仿真
      bool todayFinished = false;
      int securityGuard = 0; // 防止单日答题陷入死循环
      
      while (!todayFinished && securityGuard < 100) {
        securityGuard++;
        var getWordRes = await studyBo.getWord(false, false);
        if (!getWordRes.success) {
          break;
        }
        
        final data = getWordRes.data!;
        if (data.finished == true) {
          todayFinished = true;
          break;
        }
        
        if (data.stepIndex == 1) {
          // 列表浏览环节
          var completeListRes = await studyBo.completeListStepForCurrentBatch();
          expect(completeListRes.success, true);
        } else {
          // En2Ch 答题环节
          final currentWord = data.learningWord!;
          // 为了加速毕业并百分之百收敛，如果一个单词学过超过 1 次(learnedTimes >= 1)，我们就标记为已掌握（毕业）
          // 否则用 FSRS Rating Good 答对
          bool isMastered = currentWord.learnedTimes >= 1;
          await studyBo.getWord(isMastered, true, fsrsRating: FsrsRating.good);
        }
      }

      await studyBo.saveDakaRecord("第 ${loopCount + 2} 天打卡！");
    }

    // ============================================
    // 最终断言 (整书学完 Oracle)
    // ============================================
    print('\n[Final Assert] 🏁 校验整书毕业的终极数据一致性...');
    
    // 1. 验证整本书 8 个词是否都已经在 MasteredWords 表（毕业）
    final allMastered = await db.masteredWordsDao.getMasteredWordsForUser(testUser.id);
    print('毕业单词总数: ${allMastered.length}，包含单词IDs: ${allMastered.map((e) => e.wordId).toList()}');
    expect(allMastered.length, 8); // 全书 8 个单词必须全部实现毕业

    // 2. 检查错词本记录累计（由于每日重置，最终阶段错词本应已被清空）
    final allWrongWords = await db.select(db.userWrongWords).get();
    expect(allWrongWords.isEmpty, true);

    // 3. 打卡总天数与连续打卡统计
    userInDb = await db.usersDao.getUserById(testUser.id);
    print('最高连续打卡天数: ${userInDb!.maxContinuousDakaDayCount}，累计打卡: ${userInDb.dakaDayCount}');
    expect(userInDb.dakaDayCount > 2, true);
    expect(userInDb.continuousDakaDayCount > 2, true);

    // 4. 再次调用备词，应返回 finished 和整书背完标志
    prepResult = await LearningService.prepareTodayStudy(true);
    expect(prepResult.success, false); // 今日没有可备新词/复习词，返回失败

    // 等待后台 unawaited 任务执行完毕，防止出现 Can't re-open database 警告
    await Future.delayed(const Duration(milliseconds: 100));
    print('🎉 所有端到端长周期仿真学习、多天打卡及 FSRS 数据收敛断言全部完美通过！');
  });
}
