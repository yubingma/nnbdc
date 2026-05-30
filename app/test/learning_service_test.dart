import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/learning_service.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  final now = AppClock.now();

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
        unit: 0,
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
      // 用户的词库目标突然改成了 3，并确保日期为今天 (不触发新的一天逻辑)
      testUser = testUser.copyWith(
        wordsPerDay: 3,
        lastLearningDate: Value(AppClock.today()),
      );
      Global.updateUserCache(testUser);

      for (int i = 1; i <= 10; i++) {
        await db.into(db.learningWords).insert(LearningWord(
          userId: testUser.id,
          wordId: 'word_$i',
          addTime: now,
          addDay: 1,
          batchId: 1,
          lastLearningDate: AppClock.today(),
          stability: 0.0,
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
          stability: 0.0, // 确保有初始值否则 FSRS 查询会跳过它
          isTodayNewWord: true,
          learnedTimes: 1, // <--- 已学1遍
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

    test('所有书桌词书都已学完的场景（词汇枯竭）', () async {
      // 1. 把 setUp 里生成的这 10 个词全部设定为已加入 learning_words 并具有超高 stability（已毕业）
      for (int i = 1; i <= 10; i++) {
        await db.into(db.learningWords).insert(LearningWord(
          userId: testUser.id,
          wordId: 'word_$i',
          addTime: now,
          addDay: 1,
          batchId: 0,
          stability: 5.0, // 低于毕业阈值（不被自动清理），但处于复习等待中
          difficulty: 5.0,
          elapsedDays: 1,
          scheduledDays: 999, // 未来很远才会过期的复习计划
          reps: 1,
          lapses: 0,
          state: 2, // 状态2一般是Review
          lastLearningDate: AppClock.today(), // 核心在于上次学习日期是今天，所以加 999 天绝对不会过期！
          isTodayNewWord: false,
          learnedTimes: 5,
          todayLearnedTimes: 0,
          learningOrder: 0,
          createTime: now,
          updateTime: now,
        ));
      }

      // 2. 然后执行取词，由于这10个词虽然在书里，但都毕业了/不需复习。且词书没有其他新词供抓。
      // 此时今日无任何待学习/待复习单词，应视为完全枯竭状态，需要正常报错引导用户换新词书。
      final result = await LearningService.prepareTodayStudy(true);

      expect(result.success, false);
      expect(result.code, 'NNBDC-0012');

      var todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
      expect(todayWords.length, 0); // 绝对抽不到任何词
    });

    test('完整生命周期全景模拟：从第一天零进度直到书桌所有词书全部学完（枯竭）', () async {
      // 准备一个独立的时间线用于精准计算跨天逻辑
      final fakeClock = FakeClock(DateTime(2026, 1, 1, 8, 0));
      AppClock.setClock(fakeClock);

      // ===================================
      // 第 1 天：开始背单词之旅
      // ===================================
      var result = await LearningService.prepareTodayStudy(true);
      expect(result.success, true);
      expect(result.data![0], 5); // 抓取 5 个新词
      expect(result.data![1], 0);

      var todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
      // 精确验证它取的是前 5 个词
      expect(todayWords.map((w) => w.wordId).toList(), ['word_1', 'word_2', 'word_3', 'word_4', 'word_5']);

      // 模拟用户在第一天认真学完了这 5 个词
      for (var lw in todayWords) {
        await db.learningWordsDao.saveEntity(lw.copyWith(
          stability: const Value(2.0), // 未达到毕业标准 (约大于8-10才毕业)
          scheduledDays: const Value(2), // FSRS 调度在 2 天后复习
          lastLearningDate: Value(AppClock.today()),
          learnedTimes: 1, // <--- MUST have learnedTimes > 0 to not be a new word!
          todayLearnedTimes: 1, // 当天产生过学习
        ), true);
      }

      // ===================================
      // 第 2 天：时间推进 1 天
      // ===================================
      fakeClock.advanceDays(1);
      
      // 第二天备考：昨天的 5 个词 scheduledDays 是 2 天，所以今天还不到期。今天只需取剩余 5 个新词！
      result = await LearningService.prepareTodayStudy(true);
      expect(result.success, true);
      expect(result.data![0], 5); // 5个全新词！
      expect(result.data![1], 0);

      todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
      // 精确验证它往下抓了后 5 个新鲜词
      expect(todayWords.map((w) => w.wordId).toList(), ['word_10', 'word_6', 'word_7', 'word_8', 'word_9']);

      // 模拟用户在第二天痛快地学完了这仅剩的 5 个新词，但基础极差，只配了 1 天的复习期
      for (var lw in todayWords) {
        await db.learningWordsDao.saveEntity(lw.copyWith(
          stability: const Value(1.0), 
          scheduledDays: const Value(1), // 会导致它们在明天的 "第 3 天" 全员到期
          lastLearningDate: Value(AppClock.today()),
          learnedTimes: 1,
          todayLearnedTimes: 1,
        ), true);
      }

      // ===================================
      // 第 3 天：时间又推进 1 天
      // ===================================
      fakeClock.advanceDays(1);

      // 第三天备考：
      // - 第 1 天的词 (1-5) 过去了 2 天 (等于它们的 scheduledDays)，到期！
      // - 第 2 天的词 (6-10) 过去了 1 天 (等于它们的 scheduledDays 1天)，也到期！
      // 今天这 10 个词全体到期交锋！因为每日计划只有5，应该根据 FSRS 复习优先级选取最急需复习的 5 个词（稳定性越低的单词越需要优先复习）
      // Day 2 词 stability=1.0, Day 1 词 stability=2.0。先选出 Day 2 词 (6-10)！
      result = await LearningService.prepareTodayStudy(true);
      expect(result.success, true);
      expect(result.data![0], 0); // 没有任何新词了，全是复习
      expect(result.data![1], 5); 

      todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
      // 因为 Day 2 的稳定性 1.0 远低于 Day 1 的 2.0，所以被优先抽出！
      expect(todayWords.map((w) => w.wordId).toList(), ['word_10', 'word_6', 'word_7', 'word_8', 'word_9']);

      // 模拟用户在第三天完美地复习了这 5 个词，并将它们直接干到了“毕业”水平（毕业稳定性常数=Constants.graduationStability，默认可能是10.0或更大）
      for (var lw in todayWords) {
        await db.learningWordsDao.saveEntity(lw.copyWith(
          stability: const Value(15.0), // 超出毕业门槛
          scheduledDays: const Value(100), // 稳若泰山
          lastLearningDate: Value(AppClock.today()),
          learnedTimes: 2, // 第二次学了
          todayLearnedTimes: 1,
        ), true);
      }

      // ===================================
      // 第 4 天：时间再推进 1 天
      // ===================================
      fakeClock.advanceDays(1);

      // 第四天备考：
      // 6-10 昨天毕业了。第一批词 1-5 昨天没挤进来，今天严重过期（3>2天）。且目前稳定性还是 2.0，未毕业。
      // 它将抽出这迟到的前 5 个词作为复习填满计划
      result = await LearningService.prepareTodayStudy(true);
      expect(result.success, true);
      expect(result.data![0], 0); 
      expect(result.data![1], 5);

      todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
      // 精准验证！果然轮到了 1-5 词的复习
      expect(todayWords.map((w) => w.wordId).toList(), ['word_1', 'word_2', 'word_3', 'word_4', 'word_5']);

      // 同样，用户神采奕奕，把这 5 个词也学到了满分毕业点之上
      for (var lw in todayWords) {
        await db.learningWordsDao.saveEntity(lw.copyWith(
          stability: const Value(12.0), // 毕业啦
          scheduledDays: const Value(100),
          lastLearningDate: Value(AppClock.today()),
          learnedTimes: 2, // 第二次复习
          todayLearnedTimes: 1,
        ), true);
      }

      // ===================================
      // 第 5 天：大结局
      // ===================================
      fakeClock.advanceDays(1);

      // 第五天备考：现在全服没有任何符合复习资格的词（10个全都进入毕业池被隐形删除或不再进入待办池），所有新词库也早榨干。
      // 此时无任何复习词及新词，大结局时应正常报错 NNBDC-0012 提示换新书。
      result = await LearningService.prepareTodayStudy(true);

      expect(result.success, false);
      expect(result.code, 'NNBDC-0012');

      todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
      expect(todayWords.length, 0); // 光秃秃的一片！恭喜结课！

      // 恢复系统时钟，以免影响以后的普通环境运行
      AppClock.reset();
    });

    test('已掌握单词（在mastered_words中）的学习记录残留不应被选入今日计划', () async {
      // 1. 创建用户的"已掌握"词书（masteredWords 表的底层依赖）
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

      // 2. 将 word_1 添加到 learning_words（模拟"已掌握但学习记录残留"：stability 为 null，learnedTimes 为 0）
      await db.into(db.learningWords).insert(LearningWord(
        userId: testUser.id,
        wordId: 'word_1',
        addTime: now,
        addDay: 1,
        stability: null, // 关键：stability 为 null → 旧的查询条件会把它选出来
        isTodayNewWord: true,
        learnedTimes: 0,  // 关键：从未学习过 → 被判定为"新词"
        todayLearnedTimes: 0,
        learningOrder: 0,
        createTime: now,
        updateTime: now,
      ));

      // 3. 将 word_3 也加入 learning_words（没有 mastered 的正常新词，应正常被选取）
      await db.into(db.learningWords).insert(LearningWord(
        userId: testUser.id,
        wordId: 'word_3',
        addTime: now,
        addDay: 1,
        stability: null,
        isTodayNewWord: true,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        learningOrder: 0,
        createTime: now,
        updateTime: now,
      ));

      // 4. 将 word_1 标记为已掌握（加入 mastered_words）
      await db.masteredWordsDao.saveMasteredWord(testUser.id, 'word_1', false, false);

      // 验证 word_1 确在 mastered 中
      final masteredIds = await db.masteredWordsDao.getMasteredWordIdSet(testUser.id);
      expect(masteredIds.contains('word_1'), true);
      expect(masteredIds.contains('word_3'), false);

      // 5. 执行今日计划生成
      final result = await LearningService.prepareTodayStudy(true);
      expect(result.success, true);

      final todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);

      // 6. 核心断言：word_1（已掌握但有残留学习记录）不应出现在今日计划中
      final word1InPlan = todayWords.any((w) => w.wordId == 'word_1');
      expect(word1InPlan, false,
          reason: '已掌握的单词（在mastered_words中）不应因其learning_words残留记录而被选入今日计划');

      // 7. word_3（正常待学习的新词）应该正常出现在今日计划中
      final word3InPlan = todayWords.any((w) => w.wordId == 'word_3');
      expect(word3InPlan, true,
          reason: '未掌握的普通新词应正常被选入今日计划，修复不应误杀正常单词');
    });

    test('genTodayWords 过滤逻辑：同日非跨天场景下排除已在mastered_words中的单词', () async {
      // 此测试验证：即使没有触发跨天清理，genTodayWords 自身也能过滤掉已掌握的单词

      // 1. 创建"已掌握"词书
      var masteredDictId = 'mock_dict_mastered_v2';
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

      // 2. 将 lastLearningDate 设为今天，避免触发跨天重置（这样 deleteMasteredWords 不会先清理）
      testUser = testUser.copyWith(lastLearningDate: Value(AppClock.today()));
      Global.updateUserCache(testUser);

      // 3. 插入 word_2 到 learning_words（残留记录：stability=null, learnedTimes=0, batchId=0）
      await db.into(db.learningWords).insert(LearningWord(
        userId: testUser.id,
        wordId: 'word_2',
        addTime: now,
        addDay: 1,
        stability: null,
        isTodayNewWord: true,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        batchId: 0,
        learningOrder: 0,
        createTime: now,
        updateTime: now,
      ));

      // 4. 插入 word_4 到 learning_words（正常未掌握的新词，也 batchId=0）
      await db.into(db.learningWords).insert(LearningWord(
        userId: testUser.id,
        wordId: 'word_4',
        addTime: now,
        addDay: 1,
        stability: null,
        isTodayNewWord: true,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        batchId: 0,
        learningOrder: 0,
        createTime: now,
        updateTime: now,
      ));

      // 5. 将 word_2 标记为已掌握
      await db.masteredWordsDao.saveMasteredWord(testUser.id, 'word_2', false, false);

      final masteredIds = await db.masteredWordsDao.getMasteredWordIdSet(testUser.id);
      expect(masteredIds.contains('word_2'), true);
      expect(masteredIds.contains('word_4'), false);

      // 6. 执行今日计划生成（batchId=0 的不会被 getTodayLearningWordsFromDb 查到，所以会进入 genTodayWords 补充）
      final result = await LearningService.prepareTodayStudy(true);
      expect(result.success, true);

      final todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);

      // 7. 核心断言：word_2（已掌握）不应出现
      final word2InPlan = todayWords.any((w) => w.wordId == 'word_2');
      expect(word2InPlan, false,
          reason: 'genTodayWords 应主动排除已在mastered_words中的单词，即使跨天清理未触发');

      // 8. 核心断言：word_4（正常新词）应该出现
      final word4InPlan = todayWords.any((w) => w.wordId == 'word_4');
      expect(word4InPlan, true,
          reason: '未掌握的普通新词应正常被选取，修复不应误杀');
    });

    test('【统计漏计修复验证】即使稳定性 stability 为 NULL，也将被正确统计为学习中', () async {
      // 往 learningWords 插入 3 个稳定度为空的新词
      final testTime = AppClock.now();
      for (int i = 8; i <= 10; i++) {
        await db.into(db.learningWords).insert(LearningWord(
          userId: testUser.id,
          wordId: 'word_$i',
          addTime: testTime,
          addDay: 1,
          stability: null,
          isTodayNewWord: true,
          learnedTimes: 0,
          todayLearnedTimes: 0,
          batchId: 0,
          learningOrder: 0,
          createTime: testTime,
          updateTime: testTime,
        ));
      }

      // 统计这本词书 'mock_dict_1' 内的学习中单词数
      final learnedCount = await db.learningWordsDao.getLearningWordsCountInDicts(testUser.id, ['mock_dict_1']);
      expect(learnedCount, 3, reason: 'stability 为 NULL 的未学新词应当正常计入学习中单词总数');
    });

    test('【幽灵新词死锁解锁验证】在学习库中但从未背过的幽灵新词能够被重新挑选并正常挑入今日计划', () async {
      // 1. 手动向 learning_words 中插入 3 个从未背过的"幽灵新词"
      // 设定为：stability 为 null, learnedTimes 为 0, lastLearningDate 为 null, batchId 为 0
      final testTime = AppClock.now();
      for (int i = 5; i <= 7; i++) {
        await db.into(db.learningWords).insert(LearningWord(
          userId: testUser.id,
          wordId: 'word_$i',
          addTime: testTime,
          addDay: 1,
          stability: null,
          isTodayNewWord: true,
          learnedTimes: 0,
          todayLearnedTimes: 0,
          batchId: 0,
          learningOrder: 0,
          createTime: testTime,
          updateTime: testTime,
        ));
      }

      // 将每日学习计划设为 3 个
      final updatedUser = testUser.copyWith(wordsPerDay: 3);
      await db.usersDao.saveUser(updatedUser, false);
      Global.updateUserCache(updatedUser);

      // 2. 执行今日计划生成（测试如果已经有行但没学过，fetchNewWordsToLearn 仍应当能够成功分配 3 个词，不抛出枯竭错误）
      final result = await LearningService.prepareTodayStudy(true);
      expect(result.success, true, reason: '幽灵新词不应导致取词量枯竭，今日计划必须生成成功');

      // 3. 从 DB 重新获取今日学习单词
      final todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
      expect(todayWords.length, 3, reason: '今日计划必须刚好分配 3 个词');

      // 4. 校验这三个幽灵词是否正确进入今日计划，且其 isTodayNewWord 依然为 true
      for (var word in todayWords) {
        expect(word.isTodayNewWord, true, reason: '未学过的幽灵新词在今日计划中应保持为新词身份');
        expect(word.batchId, 1);
      }
    });

    test('【词书取空学完免报警验证】当所有选中词书全部学完入库后，完全枯竭应当报错，有待复习词时即使数量不足也不应报错', () async {
      // 1. 将词书的所有 10 个单词都模拟导入到 learningWords 中，且设为很久以后才到期
      final testTime = AppClock.now();
      for (int i = 1; i <= 10; i++) {
        await db.into(db.learningWords).insert(LearningWord(
          userId: testUser.id,
          wordId: 'word_$i',
          addTime: testTime.subtract(const Duration(days: 10)),
          addDay: 1,
          stability: 3.0,
          difficulty: 5.0,
          elapsedDays: 10,
          scheduledDays: 100, // 100天后到期，说明今天绝不到期复习
          reps: 1,
          lapses: 0,
          state: 2,
          lastLearningDate: testTime.subtract(const Duration(days: 10)),
          isTodayNewWord: false,
          learnedTimes: 1,
          todayLearnedTimes: 0,
          batchId: 0,
          learningOrder: 0,
          createTime: testTime,
          updateTime: testTime,
        ));
      }

      // 将每日计划设为 5
      final updatedUser = testUser.copyWith(wordsPerDay: 5);
      await db.usersDao.saveUser(updatedUser, false);
      Global.updateUserCache(updatedUser);

      // 2. 执行今日计划生成
      // 此时：今日复习词到期为 0 个，而新词因为全部在库中也无法抓取。今日实际分配单词量为 0。
      // 由于没有可学单词，应当正常报错
      var result = await LearningService.prepareTodayStudy(true);
      expect(result.success, false, reason: '无可复习词且新词全部学完时应正常报错枯竭');
      expect(result.code, 'NNBDC-0012');

      // 3. 修改其中 2 个词为今天到期（1天到期，2天前学习的）
      final word1 = await (db.select(db.learningWords)..where((lw) => lw.wordId.equals('word_1'))).getSingle();
      final word2 = await (db.select(db.learningWords)..where((lw) => lw.wordId.equals('word_2'))).getSingle();
      await db.learningWordsDao.saveEntity(word1.copyWith(
        scheduledDays: const Value(1),
        lastLearningDate: Value(testTime.subtract(const Duration(days: 2))),
      ), true);
      await db.learningWordsDao.saveEntity(word2.copyWith(
        scheduledDays: const Value(1),
        lastLearningDate: Value(testTime.subtract(const Duration(days: 2))),
      ), true);

      // 4. 再次执行今日计划生成
      // 此时分配量为 2 < 5，但因为有 2 个可复习词，应当免除报错，允许用户背这 2 个词
      result = await LearningService.prepareTodayStudy(true);
      expect(result.success, true, reason: '有到期复习词时，即使达不到每日计划的 5 个目标，也决不能报错');
      expect(result.code, '200');

      final todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
      expect(todayWords.length, 2, reason: '今日计划应当正常分配 2 个到期词');
    });
  });
}
