import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter/services.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nnbdc/api/enum.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  late StudyBo studyBo;
  AppClock.now();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async {
        return [];
      },
    );
  });

  setUp(() async {
    // 实例化一个存在内存中的 SQLite, 拥有完整的业务表结构和验证机制
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
    );
    await db.usersDao.saveUser(testUser, false);

    // 塞进 Global 变量缓存
    Global.currentUserId = 'test_user_id';
    Global.updateUserCache(testUser);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Prefs.write('currentUserId', 'test_user_id');

    // 学习步骤配置（三组）: 新词测评 En2Ch，答对/答错组为空 → 新词轨道 [En2Ch, List]
    // 旧词未配置 → 默认: 测评 En2Ch，答对组空，答错组 [Ch2En]
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

    // 2. 生成 Mock 词书和映射
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

    // 生成“已掌握”词书给用户
    await db.into(db.dicts).insert(Dict(
          id: 'mock_dict_mastered',
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

    await db.into(db.learningDicts).insert(LearningDict(
          userId: testUser.id,
          dictId: dictId,
          isPrivileged: false,
          fetchMastered: false,
          sortAlg: 'ORIGINAL',
          createTime: now,
          updateTime: now,
        ));

    // 3. 生成 5 个 Mock 词条到今天需要学习的列表中 (作为 batchId = 1，直接进入今天的学习池)
    for (int i = 1; i <= 5; i++) {
      var wordId = 'word_$i';
      await db.into(db.words).insert(Word(
            id: wordId,
            spell: 'apple_$i',
            popularity: 100,
            createTime: now,
            updateTime: now,
          ));
      
      // 为混淆选择提供释义
      await db.into(db.meaningItems).insert(MeaningItem(
            id: 'mim_$i',
            wordId: wordId,
            dictId: Global.commonDictId,
            ciXing: 'n.',
            meaning: 'apple juice $i',
            popularity: 100,
            ownerId: Global.sysUserId,
            createTime: now,
            updateTime: now,
          ));

      await db.into(db.dictWords).insert(DictWord(
            dictId: dictId,
            wordId: wordId,
            seq: i,
            unit: 0,
            createTime: now,
            updateTime: now,
          ));

      await db.into(db.learningWords).insert(LearningWord(
            userId: testUser.id,
            wordId: wordId,
            addTime: now,
            addDay: 1,
            batchId: 1, // <--- 这里是重点，batchId=1 代表这五个词是今天的批次候选
            lastLearningDate: AppClock.today(),
            stability: 0.0,
            isTodayNewWord: true,
            learnedTimes: 0,
            todayLearnedTimes: 0, // <--- 关键进度：今天学了多少个环节
            learningOrder: i,
            createTime: now,
            updateTime: now,
          ));
    }
  });

  tearDown(() async {
    await db.close();
  });

  group('StudyBo - 取下一个单词和学习流转逻辑测试', () {
    test('初始获取第一个单词: 进度为0，环节应为0 (En2Ch)', () async {
      // gotoNext=false 表示只是获取当前单词展示进度，不推进流程
      final result = await studyBo.getWord(false, false);

      expect(result.success, true);
      final wordResult = result.data!;
      expect(wordResult.finished, false);

      // 第一个词是 word_1，环节索引为 0 (对应 En2Ch)
      expect(wordResult.learningWord!.word.id, 'word_1');
      expect(wordResult.stepIndex, 0);

      // 这时刚开始学，进度应为 [0, 10] (5个词 * 2个环节: 测评 En2Ch + List)
      expect(wordResult.progress![0], 0);
      expect(wordResult.progress![1], 10);
    });

    test('推进一个环节(gotoNext=true)：正确叠加进度并跳到 List(或下一个词)', () async {
      // 第一次答对：gotoNext=true 会保存记录，增加 learnedTimes 和 todayLearnedTimes
      // 我们在此刻还可以给一个 FSRS 打分
      final result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
      expect(result.success, true);

      // 为了看效果，我们在推进一步后获取现在该学哪个词。注意，刚才通过 gotoNext=true，
      // 其实 getWord 内部分两步：先用传进去的值推进(把当前 current 进度+1)，再去找下一次进度对应的事。
      // 它返回的值已经是"推导后的下一个"或者"处于List环节"。
      
      // 第一个词 word_1 的 todayLearnedTimes 会从 0 -> 1。
      // List 配置也是 1。一旦 List 它就会返回一个空的模式 (列表页面显示)。
      final nextWordResult = result.data!;

      // 这时候处于 List 模式时，getWord 实际上在内部构建的 Result 中，
      // 如果 isListStep 命中，它会强制使得 currentStepIndex 为 List 的索引，但这本身可能是刚推过的那个词的进度。
      // 所以我们直接看看库里的真实影响：
      var updatedWord1 = await (db.select(db.learningWords)..where((w) => w.wordId.equals('word_1'))).getSingle();

      // 测评答对且新词答对组为空 → 自然步进至 List（+1）
      expect(updatedWord1.todayLearnedTimes, 1);
      // 有了 fsrs rating, 所以 stability 有了一个基础初始值
      expect(updatedWord1.stability, greaterThan(0.0));

      // 因为 word_1 更新了 1 进度，今天它的优先度降低了，接下来应该推导到 word_2（它的进度为 0）
      expect(nextWordResult.learningWord!.word.id, 'word_2');
      expect(nextWordResult.stepIndex, 0);
    });

    test('标记完全掌握跳过逻辑: isWordMastered = true 时直接完成', () async {
      final result = await studyBo.getWord(true, true);
      expect(result.success, true);

      // 验证它确实落入了已掌握词库表
      var masteredRec = await (db.select(db.dictWords)..where((w) => w.wordId.equals('word_1') & w.dictId.equals('mock_dict_mastered'))).getSingleOrNull();
      expect(masteredRec, isNotNull);

      // 由于 word_1 被标记已掌握，如果接下来我们再拉下一个词去展示，就会自动跳过 word_1。
      final fetchNext = await studyBo.getWord(false, false);
      
      // 这个 fetchNext 获取到的不再是 word_1，而是 word_2！且进度因为 word_1 被视为完成，自动折合为 2 分进度(也就是 2/10 + ...)
      expect(fetchNext.data!.learningWord!.word.id, 'word_2');
      expect(fetchNext.data!.progress![0], greaterThanOrEqualTo(2));
    });

    test('答错 FsrsRating.again 时：自动加入错词表', () async {
      // 当前是 word_1，回答了 again
      final result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
      expect(result.success, true);

      // 验证是否已进入错词映射表 user_wrong_words
      var wrongRec = await (db.select(db.userWrongWords)..where((w) => w.wordId.equals('word_1'))).getSingleOrNull();
      expect(wrongRec, isNotNull);
    });

    test('模拟所有单词完成学习：跨越环节和提取完成状态', () async {
      // 我们用 update 强行把所有的词全都标记为学满今天次数
      for (int i = 1; i <= 5; i++) {
        var lw = await (db.select(db.learningWords)..where((w) => w.wordId.equals('word_$i'))).getSingle();
        await StudyCacheManager().saveAndSyncWordState(db, lw.copyWith(
          todayLearnedTimes: 2, // 达到该词轨道长度(2: 测评 + List)
          learnedTimes: 2,
        ));
      }

      // 这个时候如果再调 getWord
      final result = await studyBo.getWord(false, false);
      expect(result.success, true);
      expect(result.data!.finished, true); // 返回结束标记
    });
  });

  group('StudyBo - FSRS 状态机（学习/复习事件区分）', () {
    // 重建三组配置: 新词测评 En2Ch，答对/答错组均 [Ch2En]
    // → 评分后轨道 [En2Ch, Ch2En, List]（2 个评分环节 + List），用于模拟当天多次评分
    Future<void> setupThreeSteps() async {
      await db.delete(db.userStudySteps).go();
      final now = AppClock.now();
      Future<void> insert(String group, String studyStep) async {
        await db.into(db.userStudySteps).insert(UserStudyStep(
              userId: testUser.id,
              scope: 'new',
              group: group,
              studyStep: studyStep,
              seq: 0,
              state: 'Active',
              createTime: now,
              updateTime: now,
            ));
      }

      await insert('check', 'En2Ch');
      await insert('correct', 'Ch2En');
      await insert('wrong', 'Ch2En');
    }

    // 把其他 4 个词置为今日已学完，确保 getWord 定位到指定词
    Future<void> finishOtherWords(String wordId) async {
      for (int i = 1; i <= 5; i++) {
        final id = 'word_$i';
        if (id == wordId) continue;
        final lw = await (db.select(db.learningWords)..where((w) => w.wordId.equals(id))).getSingle();
        await db.learningWordsDao.saveEntity(lw.copyWith(
          todayLearnedTimes: 3, // 未评分新词轨道 [En2Ch, List] 长 2，3 已走完
          learnedTimes: 3,
        ), false);
      }
    }

    Future<void> setWordFsrs(String wordId, {
      required double stability,
      required double difficulty,
      required int elapsedDays,
      required int scheduledDays,
      required int reps,
      required int lapses,
      required int state,
      required int todayLearnedTimes,
      required int learnedTimes,
      required DateTime lastLearningDate,
      // 可选的"今天首条评分日志"（固化当天学习/复习轨道）：
      // 同一词当天已评分过的场景必须携带，模拟真实不变量"评过分必有一条今日日志"
      int? firstLogElapsedDays,
      int? firstLogRating,
    }) async {
      final lw = await (db.select(db.learningWords)..where((w) => w.wordId.equals(wordId))).getSingle();
      await db.learningWordsDao.saveEntity(lw.copyWith(
        stability: Value(stability),
        difficulty: Value(difficulty),
        elapsedDays: Value(elapsedDays),
        scheduledDays: Value(scheduledDays),
        reps: Value(reps),
        lapses: Value(lapses),
        state: Value(state),
        todayLearnedTimes: todayLearnedTimes,
        learnedTimes: learnedTimes,
        lastLearningDate: Value(lastLearningDate),
      ), false);
      if (firstLogElapsedDays != null && firstLogRating != null) {
        // 预置日志即"今天首条评分日志"：清掉该词历史日志保证重置语义与主键唯一
        await (db.delete(db.learningLogs)
              ..where((l) => l.userId.equals(testUser.id) & l.wordId.equals(wordId)))
            .go();
        await db.learningLogsDao.saveEntity(LearningLog(
          id: 'preset_log_$wordId',
          userId: testUser.id,
          wordId: wordId,
          rating: firstLogRating,
          stability: stability,
          difficulty: difficulty,
          elapsedDays: firstLogElapsedDays,
          scheduledDays: scheduledDays,
          createTime: AppClock.now(),
          updateTime: AppClock.now(),
        ), false);
      }
    }

    Future<LearningWord> wordOf(String wordId) async {
      return (db.select(db.learningWords)..where((w) => w.wordId.equals(wordId))).getSingle();
    }

    test('新词首次评分走 init（stability 从 0 起步）', () async {
      await setupThreeSteps();
      await finishOtherWords('word_1');
      // setUp 数据 stability=0.0, todayLearnedTimes=0 → 首次评分
      final result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
      expect(result.success, true);
      final w = await wordOf('word_1');
      expect(w.stability, 2.4);
      expect(w.reps, 1);
      expect(w.state, FsrsState.learning.value);
    });

    test('当天第二次评分（巩固环节）走 relearn 重设：hard 降级', () async {
      await setupThreeSteps();
      await finishOtherWords('word_1');
      await setWordFsrs('word_1',
        stability: 2.4, difficulty: 3.05, elapsedDays: 0, scheduledDays: 2,
        reps: 1, lapses: 0, state: FsrsState.learning.value,
        todayLearnedTimes: 1, learnedTimes: 1, lastLearningDate: AppClock.today(),
        firstLogElapsedDays: 0, firstLogRating: FsrsRating.good.value);

      final result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.hard);
      expect(result.success, true);
      final w = await wordOf('word_1');
      expect(w.stability, 0.6); // 重设，不再是"hard 被吞保持 2.4"
      expect(w.reps, 2);
      expect(w.lapses, 0);
      // Ch2En 是 3 步序列的最后一个评分环节 → 提交后无剩余评分环节 → review
      expect(w.state, FsrsState.review.value);
      expect(w.todayLearnedTimes, 2);
    });

    test('当天巩固环节答对维持/恢复：again 后可 relearn good 恢复 2.4', () async {
      await setupThreeSteps();
      await finishOtherWords('word_1');
      await setWordFsrs('word_1',
        stability: 0.4, difficulty: 4.93, elapsedDays: 0, scheduledDays: 1,
        reps: 1, lapses: 1, state: FsrsState.learning.value,
        todayLearnedTimes: 1, learnedTimes: 1, lastLearningDate: AppClock.today(),
        firstLogElapsedDays: 0, firstLogRating: FsrsRating.good.value);

      final result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
      expect(result.success, true);
      final w = await wordOf('word_1');
      expect(w.stability, 2.4); // 当天答对可恢复（不再卡死在 0.4）
      expect(w.state, FsrsState.review.value);
    });

    test('最后评分环节答错 → relearning（明日重现）', () async {
      await setupThreeSteps();
      await finishOtherWords('word_1');
      await setWordFsrs('word_1',
        stability: 2.4, difficulty: 3.05, elapsedDays: 0, scheduledDays: 2,
        reps: 1, lapses: 0, state: FsrsState.learning.value,
        todayLearnedTimes: 1, learnedTimes: 1, lastLearningDate: AppClock.today(),
        firstLogElapsedDays: 0, firstLogRating: FsrsRating.good.value);

      final result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
      expect(result.success, true);
      final w = await wordOf('word_1');
      expect(w.stability, 0.4); // 重设 0.4，而非清零 0.1
      expect(w.lapses, 1);
      expect(w.state, FsrsState.relearning.value);
      expect(w.scheduledDays, 1); // 明日重现
    });

    test('跨天首次评分（复习事件）走 next：稳定性增长', () async {
      await setupThreeSteps();
      await finishOtherWords('word_1');
      final yesterday = AppClock.today().subtract(const Duration(days: 1));
      await setWordFsrs('word_1',
        stability: 2.4, difficulty: 3.05, elapsedDays: 0, scheduledDays: 2,
        reps: 1, lapses: 0, state: FsrsState.learning.value,
        todayLearnedTimes: 0, learnedTimes: 1, lastLearningDate: yesterday);

      final result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
      expect(result.success, true);
      final w = await wordOf('word_1');
      expect(w.stability, greaterThan(2.4)); // 复习公式增长
      expect(w.state, FsrsState.review.value);
      // 学一半词次日走复习轨道：测评答对 +1 进 List（步进至 1）
      expect(w.todayLearnedTimes, 1);
    });

    test('学一半词次日检验（learning 跨天）同样走 next', () async {
      await setupThreeSteps();
      await finishOtherWords('word_1');
      final yesterday = AppClock.today().subtract(const Duration(days: 1));
      await setWordFsrs('word_1',
        stability: 2.4, difficulty: 3.05, elapsedDays: 0, scheduledDays: 2,
        reps: 1, lapses: 0, state: FsrsState.learning.value,
        todayLearnedTimes: 0, learnedTimes: 1, lastLearningDate: yesterday);

      final result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
      expect(result.success, true);
      final w = await wordOf('word_1');
      expect(w.state, FsrsState.relearning.value); // 跨天答错进入重学
      expect(w.scheduledDays, 1);
    });

    test('复习轨道恢复环节：relearning 当天答对 → review，再错 → relearning', () async {
      await setupThreeSteps();
      await finishOtherWords('word_1');
      // 模拟：复习词测评答错后 state=relearning, stability=0.4, 今天已评一次分
      await setWordFsrs('word_1',
        stability: 0.4, difficulty: 4.93, elapsedDays: 0, scheduledDays: 1,
        reps: 2, lapses: 2, state: FsrsState.relearning.value,
        todayLearnedTimes: 1, learnedTimes: 2, lastLearningDate: AppClock.today(),
        firstLogElapsedDays: 1, firstLogRating: FsrsRating.again.value);

      // 恢复环节答对
      var result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
      expect(result.success, true);
      var w = await wordOf('word_1');
      expect(w.stability, 2.4);
      expect(w.state, FsrsState.review.value); // 恢复成功，今日完成
      expect(w.lapses, 2); // good 不新增 lapse

      // 重置再模拟恢复环节答错
      await setWordFsrs('word_1',
        stability: 0.4, difficulty: 4.93, elapsedDays: 0, scheduledDays: 1,
        reps: 2, lapses: 2, state: FsrsState.relearning.value,
        todayLearnedTimes: 1, learnedTimes: 2, lastLearningDate: AppClock.today(),
        firstLogElapsedDays: 1, firstLogRating: FsrsRating.again.value);
      result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
      expect(result.success, true);
      w = await wordOf('word_1');
      expect(w.stability, 0.4);
      expect(w.state, FsrsState.relearning.value); // 明日重现
      expect(w.lapses, 3);
    });

    test('复习词测评答错不跳过恢复（todayLearnedTimes +1）', () async {
      await setupThreeSteps();
      await finishOtherWords('word_1');
      final yesterday = AppClock.today().subtract(const Duration(days: 1));
      await setWordFsrs('word_1',
        stability: 2.4, difficulty: 3.05, elapsedDays: 0, scheduledDays: 2,
        reps: 1, lapses: 0, state: FsrsState.review.value,
        todayLearnedTimes: 0, learnedTimes: 1, lastLearningDate: yesterday);

      final result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
      expect(result.success, true);
      final w = await wordOf('word_1');
      expect(w.state, FsrsState.relearning.value);
      expect(w.todayLearnedTimes, 1); // 不跳过：还需走恢复环节
    });

    test('复习轨道答错走答错组后 completeListStepForCurrentBatch 按轨道推进 List', () async {
      await setupThreeSteps();
      await finishOtherWords('word_1');
      final yesterday = AppClock.today().subtract(const Duration(days: 1));
      await setWordFsrs('word_1',
        stability: 2.4, difficulty: 3.05, elapsedDays: 0, scheduledDays: 2,
        reps: 1, lapses: 0, state: FsrsState.review.value,
        todayLearnedTimes: 0, learnedTimes: 1, lastLearningDate: yesterday);

      // 测评答错 → 默认答错组 [反向互补=Ch2En] 非空 → +1 进入答错组环节
      await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
      var w = await wordOf('word_1');
      expect(w.todayLearnedTimes, 1);
      expect(w.state, FsrsState.relearning.value);

      // 答错组环节答对 → +1 → 轨道 [En2Ch, Ch2En, List] 的 List 位置
      await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
      w = await wordOf('word_1');
      expect(w.todayLearnedTimes, 2);
      expect(w.state, FsrsState.review.value);

      // 完成列表学习：判据按该词自身轨道，推进到 3（轨道走完）
      final completeRes = await studyBo.completeListStepForCurrentBatch();
      expect(completeRes.success, true);
      w = await wordOf('word_1');
      expect(w.todayLearnedTimes, 3);
    });

    test('复习轨道测评答对且答对组为空（默认）：+1 进入 List 环节，完成 List 后 finished', () async {
      await setupThreeSteps();
      await finishOtherWords('word_1');
      final yesterday = AppClock.today().subtract(const Duration(days: 1));
      await setWordFsrs('word_1',
        stability: 2.4, difficulty: 3.05, elapsedDays: 0, scheduledDays: 2,
        reps: 1, lapses: 0, state: FsrsState.review.value,
        todayLearnedTimes: 0, learnedTimes: 1, lastLearningDate: yesterday);

      // 未设置旧词规则 → 答对组空 → 测评答对 +1 进入 List 环节
      await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
      var w = await wordOf('word_1');
      expect(w.todayLearnedTimes, 1);
      expect(w.state, FsrsState.review.value);

      // 该批次处于 List 环节，getWord 返回 List 环节
      final res = await studyBo.getWord(false, false);
      expect(res.success, true);
      expect(res.data!.stepIndex, 1);

      // 完成列表学习后，该词推进到 2（轨道走完），今日 finished
      final completeRes = await studyBo.completeListStepForCurrentBatch();
      expect(completeRes.success, true);
      w = await wordOf('word_1');
      expect(w.todayLearnedTimes, 2);

      final finishRes = await studyBo.getWord(false, false);
      expect(finishRes.success, true);
      expect(finishRes.data!.finished, true);
    });

    test('整批复习词全部答对且答对组为空：5个词依次测完后统一进入 List 环节，完成 List 后整批 finished', () async {
      await setupThreeSteps();
      final yesterday = AppClock.today().subtract(const Duration(days: 1));
      for (int i = 1; i <= 5; i++) {
        await setWordFsrs('word_$i',
          stability: 2.4, difficulty: 3.05, elapsedDays: 0, scheduledDays: 2,
          reps: 1, lapses: 0, state: FsrsState.review.value,
          todayLearnedTimes: 0, learnedTimes: 1, lastLearningDate: yesterday);
      }

      // 依次完成 5 个词的测评打分 (Good)
      for (int i = 1; i <= 5; i++) {
        final res = await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
        expect(res.success, true);
        final w = await wordOf('word_$i');
        expect(w.todayLearnedTimes, 1); // 步进至 1 (List 索引)
      }

      // 5 个词全部测完，当前环节应为 List 环节
      final listRes = await studyBo.getWord(false, false);
      expect(listRes.success, true);
      expect(listRes.data!.stepIndex, 1);

      // 调用 completeListStepForCurrentBatch 批量完成 List
      final completeRes = await studyBo.completeListStepForCurrentBatch();
      expect(completeRes.success, true);

      // 验证 5 个词全部推进到 2 (轨道走完)，整批 finished
      for (int i = 1; i <= 5; i++) {
        final w = await wordOf('word_$i');
        expect(w.todayLearnedTimes, 2);
      }

      final finishRes = await studyBo.getWord(false, false);
      expect(finishRes.success, true);
      expect(finishRes.data!.finished, true);
    });
  });
}
