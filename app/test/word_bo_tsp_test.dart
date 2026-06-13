import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/local_embedding_cache.dart';

void main() {
  late MyDatabase db;
  final now = AppClock.now();
  final String dictId = 'tsp_test_dict';
  final String userId = 'test_user_id';

  Uint8List createEmbedding(List<int> activeBits) {
    final list = Uint8List(256);
    for (final bit in activeBits) {
      final byteIdx = bit ~/ 8;
      final bitIdx = bit % 8;
      list[byteIdx] |= 1 << bitIdx;
    }
    return list;
  }

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);

    // Mock user
    final user = User(
      id: userId,
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
      isInputor: true, // Allow editing dicts
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
    await db.usersDao.saveUser(user, false);
    Global.currentUserId = userId;
    Global.updateUserCache(user);

    // Mock dict
    await db.into(db.dicts).insert(Dict(
      id: dictId,
      name: 'TSP Test Book',
      wordCount: 0,
      isShared: false,
      isReady: true,
      ownerId: userId,
      visible: true,
      editable: true,
      deletable: false,
      createTime: now,
      updateTime: now,
    ));



    // Clear caches
    WordBo.clearAllTspCache();
  });

  tearDown(() async {
    await db.close();
  });

  group('WordBo TSP Semantic Sort Tests', () {
    test('TSP path calculation and memory cache validation', () async {
      // 1. Insert 3 words with coordinates such that the default order in SQLite is w1, w2, w3,
      // but closest path starting from w1 is w1 -> w3 -> w2.
      await db.into(db.words).insert(Word(
        id: 'w1', spell: 'w1', popularity: 1, embedding1bit: createEmbedding([0]),
        createTime: now, updateTime: now,
      ));
      await db.into(db.words).insert(Word(
        id: 'w2', spell: 'w2', popularity: 1, embedding1bit: createEmbedding([1, 2]),
        createTime: now, updateTime: now,
      ));
      await db.into(db.words).insert(Word(
        id: 'w3', spell: 'w3', popularity: 1, embedding1bit: createEmbedding([0, 1]),
        createTime: now, updateTime: now,
      ));

      // Insert relations in dictWords
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w1', seq: 1, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w2', seq: 2, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w3', seq: 3, unit: 0, createTime: now, updateTime: now));

      // 2. Fetch TSP list and verify it is indeed w1 -> w3 -> w2
      final wordBo = WordBo();
      final list1 = await wordBo.getTspSortedWordIdsInternal(dictId);
      expect(list1, ['w1', 'w3', 'w2']);

      // 3. Verify that the cache works by checking if we get the exact same instance/elements
      final list2 = await wordBo.getTspSortedWordIdsInternal(dictId);
      expect(identical(list1, list2), true);
    });

    test('getDictWordsForAPage correctly applies SEMANTIC sort using TSP', () async {
      // Setup same words
      await db.into(db.words).insert(Word(id: 'w1', spell: 'w1', popularity: 1, embedding1bit: createEmbedding([0]), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w2', spell: 'w2', popularity: 1, embedding1bit: createEmbedding([1, 2]), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w3', spell: 'w3', popularity: 1, embedding1bit: createEmbedding([0, 1]), createTime: now, updateTime: now));

      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w1', seq: 1, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w2', seq: 2, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w3', seq: 3, unit: 0, createTime: now, updateTime: now));

      final wordBo = WordBo();
      final paged = await wordBo.getDictWordsForAPage(dictId, 0, 10, sortAlg: 'SEMANTIC');
      
      // Verify page results order matches TSP (w1, w3, w2)
      final pagedWordIds = paged.rows.map((dw) => dw.word.id).toList();
      expect(pagedWordIds, ['w1', 'w3', 'w2']);

      // Test offset/limit slicing
      final pagedSlice = await wordBo.getDictWordsForAPage(dictId, 1, 1, sortAlg: 'SEMANTIC');
      expect(pagedSlice.rows.map((dw) => dw.word.id).toList(), ['w3']);
    });

    test('getDictWordOrder returns correct TSP index', () async {
      await db.into(db.words).insert(Word(id: 'w1', spell: 'w1', popularity: 1, embedding1bit: createEmbedding([0]), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w2', spell: 'w2', popularity: 1, embedding1bit: createEmbedding([1, 2]), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w3', spell: 'w3', popularity: 1, embedding1bit: createEmbedding([0, 1]), createTime: now, updateTime: now));

      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w1', seq: 1, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w2', seq: 2, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w3', seq: 3, unit: 0, createTime: now, updateTime: now));

      final wordBo = WordBo();
      // TSP order is: w1 (index 0), w3 (index 1), w2 (index 2)
      final orderW1 = await wordBo.getDictWordOrder(dictId, 'w1', sortAlg: 'SEMANTIC');
      final orderW2 = await wordBo.getDictWordOrder(dictId, 'w2', sortAlg: 'SEMANTIC');
      final orderW3 = await wordBo.getDictWordOrder(dictId, 'w3', sortAlg: 'SEMANTIC');

      expect(orderW1.data, 1);
      expect(orderW2.data, 3);
      expect(orderW3.data, 2);
    });

    test('Word addition and removal clears cache', () async {
      await db.into(db.words).insert(Word(id: 'w1', spell: 'w1', popularity: 1, embedding1bit: createEmbedding([0]), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w2', spell: 'w2', popularity: 1, embedding1bit: createEmbedding([1, 2]), createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w1', seq: 1, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w2', seq: 2, unit: 0, createTime: now, updateTime: now));

      final wordBo = WordBo();
      final initialList = await wordBo.getTspSortedWordIdsInternal(dictId);
      expect(initialList, ['w1', 'w2']);

      // Add word w3 -> should invalidate cache
      await db.into(db.words).insert(Word(id: 'w3', spell: 'w3', popularity: 1, embedding1bit: createEmbedding([0, 1]), createTime: now, updateTime: now));
      await wordBo.addWordToCustomDict(dictId, 'w3');

      // Fetch again and verify cache was updated
      final afterAddList = await wordBo.getTspSortedWordIdsInternal(dictId);
      expect(identical(initialList, afterAddList), false);
      expect(afterAddList, ['w1', 'w3', 'w2']);

      // Remove word w2 -> should invalidate cache
      await wordBo.removeWordFromDict(dictId, 'w2', userId);
      final afterRemoveList = await wordBo.getTspSortedWordIdsInternal(dictId);
      expect(identical(afterAddList, afterRemoveList), false);
      expect(afterRemoveList, ['w1', 'w3']);
    });

    test('ThrottledDbSyncService reset/completion clears all TSP cache', () async {
      await db.into(db.words).insert(Word(id: 'w1', spell: 'w1', popularity: 1, embedding1bit: createEmbedding([0]), createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w1', seq: 1, unit: 0, createTime: now, updateTime: now));

      final wordBo = WordBo();
      final initialList = await wordBo.getTspSortedWordIdsInternal(dictId);
      expect(initialList, ['w1']);

      // Invalidate all caches via WordBo directly (which ThrottledDbSyncService will call)
      WordBo.clearAllTspCache();

      final listAfterClear = await wordBo.getTspSortedWordIdsInternal(dictId);
      expect(identical(initialList, listAfterClear), false);
    });

    test('TSP sorting using LocalEmbeddingCache high performance path', () async {
      // 1. Insert 3 words
      await db.into(db.words).insert(Word(
        id: 'w1', spell: 'w1', popularity: 1, embedding1bit: createEmbedding([0]),
        createTime: now, updateTime: now,
      ));
      await db.into(db.words).insert(Word(
        id: 'w2', spell: 'w2', popularity: 1, embedding1bit: createEmbedding([1, 2]),
        createTime: now, updateTime: now,
      ));
      await db.into(db.words).insert(Word(
        id: 'w3', spell: 'w3', popularity: 1, embedding1bit: createEmbedding([0, 1]),
        createTime: now, updateTime: now,
      ));

      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w1', seq: 1, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w2', seq: 2, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w3', seq: 3, unit: 0, createTime: now, updateTime: now));

      // 2. Initialize the LocalEmbeddingCache
      await LocalEmbeddingCache.instance.initialize(db);
      expect(LocalEmbeddingCache.instance.isInitialized, true);

      // 3. Verify it does sorting correctly using cache and signatures
      final wordBo = WordBo();
      final list = await wordBo.getTspSortedWordIdsInternal(dictId);
      expect(list, ['w1', 'w3', 'w2']);

      // Reset cache for safety
      LocalEmbeddingCache.instance.reset();
    });

    test('TSP database cache persistence and invalidation', () async {
      await db.into(db.words).insert(Word(id: 'w1', spell: 'w1', popularity: 1, embedding1bit: createEmbedding([0]), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w2', spell: 'w2', popularity: 1, embedding1bit: createEmbedding([1, 2]), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w3', spell: 'w3', popularity: 1, embedding1bit: createEmbedding([0, 1]), createTime: now, updateTime: now));

      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w1', seq: 1, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w2', seq: 2, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w3', seq: 3, unit: 0, createTime: now, updateTime: now));

      final wordBo = WordBo();
      
      // 1. 计算前，数据库中的 semanticSeq 应该全为 null
      var dwsBefore = await (db.select(db.dictWords)..where((dw) => dw.dictId.equals(dictId))).get();
      for (final dw in dwsBefore) {
        expect(dw.semanticSeq, null);
      }

      // 2. 第一次运行排序，将触发计算，并在异步中写入本地数据库缓存
      final sortedIds = await wordBo.getTspSortedWordIdsInternal(dictId);
      expect(sortedIds, ['w1', 'w3', 'w2']);

      // 稍作等待以确保异步数据库写入完成
      await Future.delayed(const Duration(milliseconds: 100));

      // 3. 校验数据库中的 semanticSeq 是否已正确设置 (对应 'w1'->1, 'w3'->2, 'w2'->3)
      var dw1 = await db.dictWordsDao.getById(dictId, 'w1');
      var dw2 = await db.dictWordsDao.getById(dictId, 'w2');
      var dw3 = await db.dictWordsDao.getById(dictId, 'w3');
      expect(dw1?.semanticSeq, 1);
      expect(dw2?.semanticSeq, 3);
      expect(dw3?.semanticSeq, 2);

      // 4. 清除内存和数据库缓存
      WordBo.clearTspCache(dictId);
      await Future.delayed(const Duration(milliseconds: 50));

      // 5. 校验清除后，数据库中的 semanticSeq 是否已重置为 null
      var dwsAfter = await (db.select(db.dictWords)..where((dw) => dw.dictId.equals(dictId))).get();
      for (final dw in dwsAfter) {
        expect(dw.semanticSeq, null);
      }
    });

    test('TSP database cache persistence and read on cold start', () async {
      final String dictId2 = 'tsp_test_dict_2';
      await db.into(db.dicts).insert(Dict(
        id: dictId2, name: 'TSP Test Book 2', wordCount: 0, isShared: false, isReady: true,
        ownerId: userId, visible: true, editable: true, deletable: false, createTime: now, updateTime: now,
      ));

      await db.into(db.words).insert(Word(id: 'w4', spell: 'w4', popularity: 1, embedding1bit: createEmbedding([0]), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w5', spell: 'w5', popularity: 1, embedding1bit: createEmbedding([1, 2]), createTime: now, updateTime: now));

      await db.into(db.dictWords).insert(DictWord(dictId: dictId2, wordId: 'w4', seq: 1, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId2, wordId: 'w5', seq: 2, unit: 0, createTime: now, updateTime: now));

      // 1. 手动写入数据库缓存。设置顺序为 w5 -> w4
      await db.dictWordsDao.updateSemanticSeqs(dictId2, ['w5', 'w4']);
      await Future.delayed(const Duration(milliseconds: 50));

      // 2. 此时内存缓存为空，运行排序，它应当直接读取数据库缓存，返回 w5, w4 (而不是计算出的 w4, w5)
      final wordBo = WordBo();
      final sortedIds = await wordBo.getTspSortedWordIdsInternal(dictId2);
      expect(sortedIds, ['w5', 'w4']);
    });
  });
}
