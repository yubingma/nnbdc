import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/pca_projection_service.dart';

void main() {
  late MyDatabase db;
  final now = AppClock.now();
  final String dictId = 'tsp_test_dict';
  final String userId = 'test_user_id';

  Uint8List createEmbedding(int activeBit) {
    final list = Uint8List(256);
    final byteIdx = activeBit ~/ 8;
    final bitIdx = activeBit % 8;
    list[byteIdx] = 1 << (7 - bitIdx);
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

    // Setup Mock PCA Config for TSP sorting (dimensions: 2048)
    final mean = List<double>.filled(2048, 0.0);
    final components = List<List<double>>.generate(2048, (i) {
      if (i == 0) return [1.0, 1.0, 1.0];
      if (i == 1) return [10.0, 10.0, 10.0];
      if (i == 2) return [1.1, 1.1, 1.1];
      return [0.0, 0.0, 0.0];
    });
    final configJson = jsonEncode({
      'mean': mean,
      'components': components,
    });
    await db.into(db.pcaProjectionConfigs).insert(PcaProjectionConfig(
      id: 'latest',
      configJson: configJson,
      updateTime: now,
    ));

    // Force load PCA config for this database instance
    await PcaProjectionService().loadConfig();

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
        id: 'w1', spell: 'w1', popularity: 1, embedding1bit: createEmbedding(0),
        createTime: now, updateTime: now,
      ));
      await db.into(db.words).insert(Word(
        id: 'w2', spell: 'w2', popularity: 1, embedding1bit: createEmbedding(1),
        createTime: now, updateTime: now,
      ));
      await db.into(db.words).insert(Word(
        id: 'w3', spell: 'w3', popularity: 1, embedding1bit: createEmbedding(2),
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
      await db.into(db.words).insert(Word(id: 'w1', spell: 'w1', popularity: 1, embedding1bit: createEmbedding(0), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w2', spell: 'w2', popularity: 1, embedding1bit: createEmbedding(1), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w3', spell: 'w3', popularity: 1, embedding1bit: createEmbedding(2), createTime: now, updateTime: now));

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
      await db.into(db.words).insert(Word(id: 'w1', spell: 'w1', popularity: 1, embedding1bit: createEmbedding(0), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w2', spell: 'w2', popularity: 1, embedding1bit: createEmbedding(1), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w3', spell: 'w3', popularity: 1, embedding1bit: createEmbedding(2), createTime: now, updateTime: now));

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
      await db.into(db.words).insert(Word(id: 'w1', spell: 'w1', popularity: 1, embedding1bit: createEmbedding(0), createTime: now, updateTime: now));
      await db.into(db.words).insert(Word(id: 'w2', spell: 'w2', popularity: 1, embedding1bit: createEmbedding(1), createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w1', seq: 1, unit: 0, createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w2', seq: 2, unit: 0, createTime: now, updateTime: now));

      final wordBo = WordBo();
      final initialList = await wordBo.getTspSortedWordIdsInternal(dictId);
      expect(initialList, ['w1', 'w2']);

      // Add word w3 -> should invalidate cache
      await db.into(db.words).insert(Word(id: 'w3', spell: 'w3', popularity: 1, embedding1bit: createEmbedding(2), createTime: now, updateTime: now));
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
      await db.into(db.words).insert(Word(id: 'w1', spell: 'w1', popularity: 1, embedding1bit: createEmbedding(0), createTime: now, updateTime: now));
      await db.into(db.dictWords).insert(DictWord(dictId: dictId, wordId: 'w1', seq: 1, unit: 0, createTime: now, updateTime: now));

      final wordBo = WordBo();
      final initialList = await wordBo.getTspSortedWordIdsInternal(dictId);
      expect(initialList, ['w1']);

      // Invalidate all caches via WordBo directly (which ThrottledDbSyncService will call)
      WordBo.clearAllTspCache();

      final listAfterClear = await wordBo.getTspSortedWordIdsInternal(dictId);
      expect(identical(initialList, listAfterClear), false);
    });
  });
}
