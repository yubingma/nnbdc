import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  final now = AppClock.now();
  final String userId1 = 'user_1';
  final String userId2 = 'user_2';

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    StudyCacheManager().clear();

    // 插入两个测试用户
    await db.usersDao.saveUser(User(
      id: userId1,
      userName: 'user1',
      password: '',
      nickName: 'User1',
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
      wordsPerDay: 10,
      dakaDayCount: 0,
      masteredWordsCount: 0,
      maxContinuousDakaDayCount: 0,
      continuousDakaDayCount: 0,
      todayStudyStarted: true,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
    ), false);

    await db.usersDao.saveUser(User(
      id: userId2,
      userName: 'user2',
      password: '',
      nickName: 'User2',
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
      wordsPerDay: 10,
      dakaDayCount: 0,
      masteredWordsCount: 0,
      maxContinuousDakaDayCount: 0,
      continuousDakaDayCount: 0,
      todayStudyStarted: true,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
    ), false);

    // 插入一些基础单词
    for (int i = 1; i <= 5; i++) {
      await db.into(db.words).insert(Word(
        id: 'word_$i',
        spell: 'word_$i',
        popularity: 100,
        createTime: now,
        updateTime: now,
      ));
    }

    // 为用户创建"已掌握"词书，供 MasteredWordsDao 使用
    await db.into(db.dicts).insertOnConflictUpdate(Dict(
      id: 'dict_mastered_$userId1',
      name: '已掌握',
      wordCount: 0,
      isShared: false,
      isReady: true,
      ownerId: userId1,
      visible: true,
      editable: false,
      deletable: false,
      createTime: now,
      updateTime: now,
    ));

    await db.into(db.dicts).insertOnConflictUpdate(Dict(
      id: 'dict_mastered_$userId2',
      name: '已掌握',
      wordCount: 0,
      isShared: false,
      isReady: true,
      ownerId: userId2,
      visible: true,
      editable: false,
      deletable: false,
      createTime: now,
      updateTime: now,
    ));
  });

  tearDown(() async {
    await db.close();
  });

  group('StudyCacheManager - 缓存与数据库一致性端到端测试', () {
    test('首次加载：缓存内容与数据库保持一致', () async {
      final String uniqueUserId = 'user_unique_1';
      // 准备数据库数据
      await db.into(db.learningWords).insert(LearningWord(
        userId: uniqueUserId,
        wordId: 'word_1',
        addTime: now,
        addDay: 1,
        batchId: 1,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        learningOrder: 1,
        isTodayNewWord: true,
        createTime: now,
        updateTime: now,
      ));

      await db.into(db.dicts).insert(Dict(
        id: 'dict_mastered_$uniqueUserId',
        name: '已掌握',
        wordCount: 0,
        isShared: false,
        isReady: true,
        ownerId: uniqueUserId,
        visible: true,
        editable: false,
        deletable: false,
        createTime: now,
        updateTime: now,
      ));

      await db.masteredWordsDao.saveMasteredWord(uniqueUserId, 'word_2', true, false);

      // 通过 CacheManager 读取
      final learningIds = await StudyCacheManager().getLearningWordIds(db, uniqueUserId);
      final masteredIds = await StudyCacheManager().getMasteredWordIds(db, uniqueUserId);
      final todayWords = await StudyCacheManager().getTodayWords(db, uniqueUserId);

      print('DEBUG: uniqueUserId=$uniqueUserId, learningIds=$learningIds');

      // 验证缓存与数据库一致
      expect(learningIds.contains('word_1'), true);
      expect(masteredIds.contains('word_2'), true);
      expect(todayWords.length, 1);
      expect(todayWords.first.wordId, 'word_1');

      // 验证内部缓存是否真的填充了
      expect(StudyCacheManager().cachedLearningWordIds, isNotNull);
      expect(StudyCacheManager().cachedMasteredWordIds, isNotNull);
      expect(StudyCacheManager().cachedTodayWords, isNotNull);
    });

    test('更新单词状态：缓存与数据库同步更新', () async {
      // 1. 初始化今日单词
      final initialWord = LearningWord(
        userId: userId1,
        wordId: 'word_1',
        addTime: now,
        addDay: 1,
        batchId: 1,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        learningOrder: 1,
        isTodayNewWord: true,
        createTime: now,
        updateTime: now,
      );
      await db.into(db.learningWords).insert(initialWord);

      // 加载进缓存
      await StudyCacheManager().getTodayWords(db, userId1);

      // 2. 更新状态
      final updatedWord = initialWord.copyWith(
        todayLearnedTimes: 1,
        learnedTimes: 1,
      );
      await StudyCacheManager().saveAndSyncWordState(db, updatedWord);

      // 3. 验证数据库
      final dbWord = await (db.select(db.learningWords)..where((tbl) => tbl.wordId.equals('word_1'))).getSingle();
      expect(dbWord.todayLearnedTimes, 1);

      // 4. 验证缓存
      final cachedWords = StudyCacheManager().cachedTodayWords;
      expect(cachedWords, isNotNull);
      expect(cachedWords!.first.todayLearnedTimes, 1);
    });

    test('标记为已掌握：缓存正确流转状态', () async {
      final initialWord = LearningWord(
        userId: userId1,
        wordId: 'word_1',
        addTime: now,
        addDay: 1,
        batchId: 1,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        learningOrder: 1,
        isTodayNewWord: true,
        createTime: now,
        updateTime: now,
      );
      await db.into(db.learningWords).insert(initialWord);

      // 预加载缓存
      await StudyCacheManager().getLearningWordIds(db, userId1);
      await StudyCacheManager().getMasteredWordIds(db, userId1);

      // 标记为已掌握
      await StudyCacheManager().saveMasteredWordAndSync(db, userId1, 'word_1');

      // 验证缓存状态流转
      expect(StudyCacheManager().cachedLearningWordIds!.contains('word_1'), false);
      expect(StudyCacheManager().cachedMasteredWordIds!.contains('word_1'), true);

      // 验证数据库
      final isMasteredInDb = await db.masteredWordsDao.isWordMastered(userId1, 'word_1');
      expect(isMasteredInDb, true);
    });

    test('删除单词：缓存与数据库同步移除', () async {
      final initialWord = LearningWord(
        userId: userId1,
        wordId: 'word_1',
        addTime: now,
        addDay: 1,
        batchId: 1,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        learningOrder: 1,
        isTodayNewWord: true,
        createTime: now,
        updateTime: now,
      );
      await db.into(db.learningWords).insert(initialWord);

      await StudyCacheManager().getTodayWords(db, userId1);
      await StudyCacheManager().getLearningWordIds(db, userId1);

      expect(StudyCacheManager().cachedTodayWords!.length, 1);

      // 删除
      await StudyCacheManager().deleteAndSyncWordState(db, initialWord);

      // 验证缓存
      expect(StudyCacheManager().cachedTodayWords!.length, 0);
      expect(StudyCacheManager().cachedLearningWordIds!.contains('word_1'), false);

      // 验证数据库
      final dbWord = await (db.select(db.learningWords)..where((tbl) => tbl.wordId.equals('word_1'))).getSingleOrNull();
      expect(dbWord, isNull);
    });

    test('用户切换：自动清空旧用户数据并加载新用户', () async {
      // User 1 的数据
      await db.into(db.learningWords).insert(LearningWord(
        userId: userId1,
        wordId: 'word_1',
        addTime: now,
        addDay: 1,
        batchId: 1,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        learningOrder: 1,
        isTodayNewWord: true,
        createTime: now,
        updateTime: now,
      ));

      // User 2 的数据
      await db.into(db.learningWords).insert(LearningWord(
        userId: userId2,
        wordId: 'word_2',
        addTime: now,
        addDay: 1,
        batchId: 1,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        learningOrder: 1,
        isTodayNewWord: true,
        createTime: now,
        updateTime: now,
      ));

      // 1. 加载 User 1
      await StudyCacheManager().getTodayWords(db, userId1);
      expect(StudyCacheManager().cachedTodayWords!.first.wordId, 'word_1');

      // 2. 切换到 User 2 读取
      await StudyCacheManager().getTodayWords(db, userId2);
      expect(StudyCacheManager().cachedTodayWords!.first.wordId, 'word_2');
    });

    test('强制刷新：数据同步不一致时强行覆盖', () async {
      // 加载空缓存
      await StudyCacheManager().getTodayWords(db, userId1);
      expect(StudyCacheManager().cachedTodayWords!.length, 0);

      // 模拟外部（如后台同步）直接插入了数据库
      await db.into(db.learningWords).insert(LearningWord(
        userId: userId1,
        wordId: 'word_1',
        addTime: now,
        addDay: 1,
        batchId: 1,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        learningOrder: 1,
        isTodayNewWord: true,
        createTime: now,
        updateTime: now,
      ));

      // 此时缓存落后
      expect(StudyCacheManager().cachedTodayWords!.length, 0);

      // 强制刷新
      await StudyCacheManager().refreshCache(db, userId1);

      // 缓存赶上
      expect(StudyCacheManager().cachedTodayWords!.length, 1);
      expect(StudyCacheManager().cachedTodayWords!.first.wordId, 'word_1');
    });
  group('StudyCacheManager - 额外一致性保障测试', () {
    test('数据库更新后缓存立即反映（通过缓存更新API）', () async {
      final initialWord = LearningWord(
        userId: userId1,
        wordId: 'word_1',
        addTime: now,
        addDay: 1,
        batchId: 1,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        learningOrder: 1,
        isTodayNewWord: true,
        createTime: now,
        updateTime: now,
      );
      
      // 使用缓存管理器存入
      await StudyCacheManager().saveAndSyncWordState(db, initialWord);
      
      // 再次读取今日单词（应当走缓存，且直接命中）
      final cachedToday = await StudyCacheManager().getTodayWords(db, userId1);
      expect(cachedToday.length, 1);
      expect(cachedToday.first.todayLearnedTimes, 0);
      
      // 修改状态
      final updated = initialWord.copyWith(todayLearnedTimes: 5);
      await StudyCacheManager().saveAndSyncWordState(db, updated);
      
      // 验证缓存
      final cachedTodayAfter = await StudyCacheManager().getTodayWords(db, userId1);
      expect(cachedTodayAfter.first.todayLearnedTimes, 5);
      
      // 验证数据库
      final dbWord = await (db.select(db.learningWords)..where((tbl) => tbl.wordId.equals('word_1'))).getSingle();
      expect(dbWord.todayLearnedTimes, 5);
    });

    test('多端增量同步：高效合并数据而不销毁全局缓存', () async {
      final initialWord = LearningWord(
        userId: userId1,
        wordId: 'word_1',
        addTime: now,
        addDay: 1,
        batchId: 1,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        learningOrder: 1,
        isTodayNewWord: true,
        createTime: now,
        updateTime: now,
      );
      await db.into(db.learningWords).insert(initialWord);

      // 加载初态缓存
      await StudyCacheManager().getTodayWords(db, userId1);
      await StudyCacheManager().getLearningWordIds(db, userId1);
      expect(StudyCacheManager().cachedTodayWords!.length, 1);

      // 云端增量同步拉回了两个变更：1. 更新 word_1 的学过次数； 2. 新增今日计划 word_2
      final cloudUpdatedWord1 = initialWord.copyWith(learnedTimes: 3, todayLearnedTimes: 2);
      final cloudNewWord2 = LearningWord(
        userId: userId1,
        wordId: 'word_2',
        addTime: now,
        addDay: 1,
        batchId: 1,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        learningOrder: 2,
        isTodayNewWord: true,
        createTime: now,
        updateTime: now,
      );

      // 模拟多端增量同步
      StudyCacheManager().mergeSyncData(db, userId1, 
        updatedLearningWords: [cloudUpdatedWord1, cloudNewWord2],
      );

      // 断言：缓存保持在内存状态（不为 null 证明未被全量清空，保持最高性能）
      expect(StudyCacheManager().cachedTodayWords, isNotNull);
      expect(StudyCacheManager().cachedTodayWords!.length, 2);

      // 断言：缓存中的数据已经静默与云端同步保持一致
      final targetWord1 = StudyCacheManager().cachedTodayWords!.firstWhere((w) => w.wordId == 'word_1');
      expect(targetWord1.learnedTimes, 3);
      expect(targetWord1.todayLearnedTimes, 2);

      final targetWord2 = StudyCacheManager().cachedTodayWords!.firstWhere((w) => w.wordId == 'word_2');
      expect(targetWord2.learningOrder, 2);
    });
  });
  });
}
