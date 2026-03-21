import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/learning_service.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  final now = AppClock.now();

  setUpAll(() {
    const MethodChannel('plugins.flutter.io/path_provider').setMockMethodCallHandler((MethodCall methodCall) async {
      return '.';
    });
    const MethodChannel('dev.fluttercommunity.plus/connectivity').setMockMethodCallHandler((MethodCall methodCall) async {
      return 'wifi';
    });
  });

  setUp(() async {
    // 实例化一个存在内存中的 SQLite, 拥有完整的业务表结构和验证机制
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);

    // 1. 生成 Mock User，每日计划是 5 个词
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
      todayStudyStarted: false,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
    );
    await db.usersDao.saveUser(testUser, false);

    // 塞进 Global 变量缓存
    Global.currentUserId = 'test_user_id';
    Global.updateUserCache(testUser);

    // 2. 生成 Mock 词书和映射
    var dictId = 'mock_dict_1';
    await db.into(db.dicts).insert(Dict(
      id: dictId,
      name: '四级核心词汇',
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
      userId: 'test_user_id',
      dictId: dictId,
      isPrivileged: false,
      fetchMastered: false,
      createTime: now,
      updateTime: now,
    ));

    // 3. 生成 10 个 Mock 词条到词书里
    for (int i = 1; i <= 10; i++) {
      var wordId = 'word_$i';
      await db.into(db.words).insert(Word(
        id: wordId,
        spell: 'apple_$i',
        popularity: 100,
        createTime: now,
        updateTime: now,
      ));
      await db.into(db.dictWords).insert(DictWord(
        dictId: dictId,
        wordId: wordId,
        seq: i,
        createTime: now,
        updateTime: now,
      ));
    }
  });

  tearDown(() async {
    await db.close();
  });

  group('LearningService - 准备当日的学习单词和取词机制', () {
    test('纯新用户第一天：取满足 wordsPerDay 的全新单词', () async {
      // 执行今日计划生成
      final result = await LearningService.prepareTodayStudy(true);

      expect(result.success, true);
      // result.data 是 [新词数, 复习词数]
      expect(result.data![0], 5);
      expect(result.data![1], 0); // 没有复习的词

      // 验证这5个词是否真正的到了 learning_words 表并且挂载了正确的批次
      var todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
      expect(todayWords.length, 5);
      
      for (var lw in todayWords) {
        expect(lw.batchId, 1);
        expect(lw.isTodayNewWord, true); // 全是新词
        expect(lw.userId, testUser.id);
      }
    });

    test('包含到期复习单词的场景：先选取到期词，再补足新词', () async {
      final pastDate = now.subtract(const Duration(days: 3));
      
      // 弄两个历史已经学习过，且现在到了复习日期（到期）的词
      await db.into(db.learningWords).insert(LearningWord(
        userId: testUser.id,
        wordId: 'word_1',
        addTime: pastDate,
        addDay: 1,
        stability: 2.5,
        difficulty: 5.0,
        elapsedDays: 3,
        scheduledDays: 1, // 间隔1天复习，但已经过了3天，必定到期
        reps: 1,
        lapses: 0,
        state: 1, // Learning状态
        lastLearningDate: pastDate, // 之前学过的日期
        isTodayNewWord: false,
        learnedTimes: 1,
        todayLearnedTimes: 0,
        learningOrder: 0,
        createTime: pastDate,
        updateTime: pastDate,
      ));

      await db.into(db.learningWords).insert(LearningWord(
        userId: testUser.id,
        wordId: 'word_2',
        addTime: pastDate,
        addDay: 1,
        stability: 3.5,
        difficulty: 5.0,
        elapsedDays: 3,
        scheduledDays: 100, // 计划一百天后，不到期！
        reps: 1,
        lapses: 0,
        state: 2, // Review状态
        lastLearningDate: pastDate,
        isTodayNewWord: false,
        learnedTimes: 1,
        todayLearnedTimes: 0,
        learningOrder: 0,
        createTime: pastDate,
        updateTime: pastDate,
      ));

      final result = await LearningService.prepareTodayStudy(true);
      expect(result.success, true);
      
      // 用户计划是 5个。word_1 到期，word_2不到期。所以应该抓取 word_1 (复习)，然后再去新词库抓 4个新词。
      var todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
      expect(todayWords.length, 5);

      // 校验结果构成: 1个老词, 4个新词
      int reviewCount = todayWords.where((w) => w.isTodayNewWord == false).length;
      int newCount = todayWords.where((w) => w.isTodayNewWord == true).length;
      
      expect(reviewCount, 1);
      expect(newCount, 4);

      // 核对那唯一一个复习词确实是 word_1 
      var reviewWord = todayWords.firstWhere((w) => !w.isTodayNewWord);
      expect(reviewWord.wordId, 'word_1');
    });

    test('Shrink 缩小每日单词数计划时的裁剪逻辑', () async {
      // 先产生10个待学习的词赋予今天
      // 用户的词库目标突然改成了 3
      testUser = testUser.copyWith(wordsPerDay: 3);
      Global.updateUserCache(testUser);

      for (int i = 1; i <= 10; i++) {
        await db.into(db.learningWords).insert(LearningWord(
          userId: testUser.id,
          wordId: 'word_$i',
          addTime: now,
          addDay: 1,
          batchId: 1,
          lastLearningDate: now,
          isTodayNewWord: true,
          learnedTimes: 0,
          todayLearnedTimes: 0, // 都还没学
          learningOrder: i,
          createTime: now,
          updateTime: now,
        ));
      }

      // 执行 prepareTodayStudy，发现库里有10个，但是计划被改成3了，应该触发 shrinkTodayWords 返回 3个。
      final result = await LearningService.prepareTodayStudy(false); // 不用补偿，单纯看缩减
      expect(result.success, true);

      var todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
      
      // 成功从10被削减为了3！
      expect(todayWords.length, 3);
      
      // 剩下的是 batch 相同的情况下 order 最靠前的1,2,3
      expect(todayWords[0].wordId, 'word_1');
      expect(todayWords[1].wordId, 'word_2');
      expect(todayWords[2].wordId, 'word_3');

      // 并验证其余7个词是不是 batch_id 真的被回退成0
      var idleWords = await (db.select(db.learningWords)..where((lw) => lw.batchId.equals(0))).get();
      expect(idleWords.length, 7);
    });

    test('未完成的前日学习会触发跨日重置 (新的一天跨天逻辑)', () async {
      // 上一次学习在昨天
      final yesterday = now.subtract(const Duration(days: 1));
      
      testUser = testUser.copyWith(
        lastLearningDate: Value(yesterday), // 把最后学习日改到昨天
      );
      Global.updateUserCache(testUser);

      // 把词库塞一个批次1（昨天没学完挂起的词）
      await db.into(db.learningWords).insert(LearningWord(
          userId: testUser.id,
          wordId: 'word_1',
          addTime: yesterday,
          addDay: 1,
          batchId: 1, // 挂着一个批次
          isTodayNewWord: true,
          learnedTimes: 0,
          todayLearnedTimes: 1, // 昨天学了1遍但没过
          learningOrder: 1,
          createTime: yesterday,
          updateTime: yesterday,
      ));

      // 强行准备今日：该跨天流程会自动把 batchId 清除，todayLearnedTimes 归零，并且作为新的一天的新鲜状态
      await LearningService.prepareTodayStudy(true);

      var updatedWord = await (db.select(db.learningWords)..where((lw) => lw.wordId.equals('word_1'))).getSingle();
      
      // todayLearnedTimes 必须被成功清理回0！
      expect(updatedWord.todayLearnedTimes, 0);
      // 它作为旧词，被重新发配到了今天的新的BatchId上 (今天生成的所有词 BatchId 也是1起步)
      expect(updatedWord.batchId, 1);
    });
  });
}
