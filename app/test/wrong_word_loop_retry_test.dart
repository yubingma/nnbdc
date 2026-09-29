import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/learning_service.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 错词循环重练（全对才通关）：
/// - 答错的词留在本环节循环重练，答对才推进环节索引
/// - 一个词在一个环节内只以首次作答计分，重练不写日志
/// - 测评答错同样留在测评环节重练，且轨道仍按首条评分走答错组
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  late StudyBo studyBo;

  /// 今日该词的评分日志条数（= 已计分的环节数）
  Future<int> logCountOf(String wordId) async {
    final rows = await (db.select(db.learningLogs)
          ..where((l) => l.userId.equals(testUser.id) & l.wordId.equals(wordId)))
        .get();
    return rows.length;
  }

  Future<LearningWord> wordOf(String wordId) async {
    return (db.select(db.learningWords)
          ..where((w) => w.userId.equals(testUser.id) & w.wordId.equals(wordId)))
        .getSingle();
  }

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => [],
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    studyBo = StudyBo();
    StudyCacheManager().clear();

    final now = AppClock.now();
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
      wordsPerDay: 1,
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
    );
    await db.usersDao.saveUser(testUser, false);

    Global.currentUserId = 'test_user_id';
    Global.updateUserCache(testUser);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Prefs.write('currentUserId', 'test_user_id');

    // 新词三组：测评 En2Ch → 答对/答错都进 Ch2En；轨道 [En2Ch, Ch2En, List]
    for (final entry in [
      (group: 'check', step: 'En2Ch', seq: 0),
      (group: 'correct', step: 'Ch2En', seq: 0),
      (group: 'wrong', step: 'Ch2En', seq: 0),
    ]) {
      await db.into(db.userStudySteps).insert(UserStudyStep(
            userId: testUser.id,
            scope: 'new',
            group: entry.group,
            studyStep: entry.step,
            seq: entry.seq,
            state: 'Active',
            createTime: now,
            updateTime: now,
          ));
    }

    const dictId = 'mock_dict_1';
    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '测试词书',
          wordCount: 1,
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

    // 只放一个词：批次即该词，每次 getWord 的评分对象都确定
    const wordId = 'word_1';
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
          lastLearningDate: null,
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
    await db.close();
  });

  /// 追加一个今日单词，用于构造多词批次（本题 setUp 默认只有 word_1）
  Future<void> addWord(String wordId, int learningOrder) async {
    final now = AppClock.now();
    await db.into(db.words).insert(Word(
          id: wordId,
          spell: wordId,
          popularity: 100,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.meaningItems).insert(MeaningItem(
          id: 'mim_$wordId',
          wordId: wordId,
          dictId: Global.commonDictId,
          ciXing: 'n.',
          meaning: '$wordId 的含义',
          popularity: 100,
          ownerId: Global.sysUserId,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.dictWords).insert(DictWord(
          dictId: 'mock_dict_1',
          wordId: wordId,
          seq: learningOrder,
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
          lastLearningDate: null,
          stability: 0.0,
          isTodayNewWord: true,
          learnedTimes: 0,
          todayLearnedTimes: 0,
          learningOrder: learningOrder,
          createTime: now,
          updateTime: now,
          isExtra: false,
        ));
  }

  test('答错的词排到本环节队尾：等组内其他词过完本环节才回来重练', () async {
    await addWord('word_2', 2);
    await addWord('word_3', 3);
    StudyCacheManager().clear();

    final order = <String>[];
    bool word1WrongOnce = false;
    for (int i = 0; i < 4; i++) {
      final res = await studyBo.getWord(false, false);
      final wordId = res.data!.learningWord!.word.id!;
      order.add(wordId);
      final wantWrong = wordId == 'word_1' && !word1WrongOnce;
      word1WrongOnce = word1WrongOnce || wantWrong;
      await studyBo.getWord(false, true,
          fsrsRating: wantWrong ? FsrsRating.again : FsrsRating.good);
    }

    expect(order, ['word_1', 'word_2', 'word_3', 'word_1'],
        reason: '错词必须排到本环节队尾，而不是紧接着原地重来（答案刚揭晓就复述没有意义）');
  });

  test('组内已答对的词不影响：答错后未作答的词仍优先于重练的词', () async {
    await addWord('word_2', 2);
    await addWord('word_3', 3);
    StudyCacheManager().clear();

    // w_1 测评答对 → 推进到 1
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);

    // 下一个应为 w_2（tLT 最小）
    var res = await studyBo.getWord(false, false);
    expect(res.data!.learningWord!.word.id, 'word_2');

    // w_2 测评答错 → 留在测评环节待重练
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);

    // 再取词：未作答的 w_3 应优先于答错待重练的 w_2
    res = await studyBo.getWord(false, false);
    expect(res.data!.learningWord!.word.id, 'word_3',
        reason: '同环节内未作答的词优先于答错待重练的词');

    // w_3 答对后，才轮到 w_2 重练
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
    res = await studyBo.getWord(false, false);
    expect(res.data!.learningWord!.word.id, 'word_2');
  });

  test('答错卡住的词不会被削减计划当作"未学"移出今日列表', () async {
    await addWord('word_2', 2);
    await addWord('word_3', 3);
    StudyCacheManager().clear();

    // word_1 测评答错 → 留在本环节重练，今日进度仍为 0
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
    expect((await wordOf('word_1')).todayLearnedTimes, 0);

    // 把计划量从 3 削减到 2：只该剔掉真正没学过的 word_3
    final words = await (db.select(db.learningWords)
          ..where((w) => w.userId.equals(testUser.id)))
        .get();
    final shrunk = await LearningService.shrinkTodayWords(testUser.id, words, 2);

    expect(shrunk.map((w) => w.wordId).toList(), ['word_1', 'word_2'],
        reason: '今天已作答过的词（含答错待重练、进度仍为 0）不得被当作未学移除');
  });

  test('初始状态：环节索引 0 为测评 En2Ch', () async {
    final result = await studyBo.getWord(false, false);
    expect(result.success, true);
    expect(result.data!.stepIndex, 0);
  });

  test('训练环节（Ch2En）答错不推进，留在本环节重练，答对才推进', () async {
    // 1. 测评首答答对 → 推进到 Ch2En
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
    expect((await wordOf('word_1')).todayLearnedTimes, 1);
    expect(await logCountOf('word_1'), 1);

    // 2. Ch2En 首答答错 → 环节索引原地不动（核心：错词留在本环节）
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
    expect((await wordOf('word_1')).todayLearnedTimes, 1,
        reason: '答错不得推进环节索引');
    expect(await logCountOf('word_1'), 2, reason: '首次作答仍需计分');

    // 3. 重练仍答错 → 索引不动，且重练不写日志
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
    expect((await wordOf('word_1')).todayLearnedTimes, 1);
    expect(await logCountOf('word_1'), 2, reason: '重练不得重复计分');

    // 4. 重练答对 → 推进到 List
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
    expect((await wordOf('word_1')).todayLearnedTimes, 2);
    expect(await logCountOf('word_1'), 2, reason: '重练答对同样不计分');
  });

  test('答错后重新取词：仍返回同一词、同一环节', () async {
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);

    final retry = await studyBo.getWord(false, false);
    expect(retry.data!.learningWord!.word.id, 'word_1');
    expect(retry.data!.stepIndex, 1, reason: '错词重练仍停留原环节');
  });

  test('测评环节答错同样留在测评重练，且重练不计分', () async {
    // 测评首答答错 → 不推进
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
    expect((await wordOf('word_1')).todayLearnedTimes, 0,
        reason: '测评答错也要重练到答对才放行');
    expect(await logCountOf('word_1'), 1);

    // 重练答对 → 才推进，走答错组（默认与答对组同为 Ch2En）
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
    expect((await wordOf('word_1')).todayLearnedTimes, 1);
    expect(await logCountOf('word_1'), 1, reason: '重练不得重复计分');
  });

  test('不变式：连续答错任意多次，环节索引不增长', () async {
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
    expect((await wordOf('word_1')).todayLearnedTimes, 1);

    for (int i = 0; i < 5; i++) {
      await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
    }

    final word = await wordOf('word_1');
    expect(word.todayLearnedTimes, 1,
        reason: '反复答错不得让进度溢出、不得提前判定今日完成');
    expect(await logCountOf('word_1'), 2);
  });

  test('答错卡住的词不会被误判为复习词（isTodayNewWord 不漂移）', () async {
    // 测评答错：进度仍为 0，但今天确实已学过（lastLearningDate 已写为今天）
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
    final stuck = await wordOf('word_1');
    expect(stuck.todayLearnedTimes, 0);
    expect(stuck.lastLearningDate, isNotNull);
    expect(stuck.isTodayNewWord, true);

    // 今日计划重排（进入学习页准备流程会走这里）：不得把新词改判为复习词
    final words = await (db.select(db.learningWords)
          ..where((w) => w.userId.equals(testUser.id)))
        .get();
    await LearningService.updateTodayLearningWords(words, AppClock.now());

    expect((await wordOf('word_1')).isTodayNewWord, true,
        reason: '今天已作答过的词，其当天轨道不得因进度仍为 0 而漂移');
  });
}
