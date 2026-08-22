import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';

void main() {
  late MyDatabase database;

  setUp(() {
    database = MyDatabase(DatabaseConnection(NativeDatabase.memory()));
  });

  tearDown(() async {
    await database.close();
  });

  group('WordsDao - getWordsWithCoordinates Unit Tests', () {
    test('retrieves only words with all three coordinates non-null', () async {
      // 1. Insert mock words with different coordinate combinations (now based on embedding1bit)
      await database.wordsDao.insertEntities([
        Word(
          id: 'apple',
          spell: 'apple',
          popularity: 1,
          embedding1bit: Uint8List(256),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'banana',
          spell: 'banana',
          popularity: 1,
          embedding1bit: null,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'cherry',
          spell: 'cherry',
          popularity: 1,
          embedding1bit: Uint8List(256),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'date',
          spell: 'date',
          popularity: 1,
          embedding1bit: null,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
      ]);

      // 2. Query words with coordinates
      final results = await database.wordsDao.getWordsWithCoordinates();

      // 3. Verify expectations
      expect(results.length, 2);
      expect(results.any((w) => w.id == 'apple'), true);
      expect(results.any((w) => w.id == 'cherry'), true);
      expect(results.any((w) => w.id == 'banana'), false);
      expect(results.any((w) => w.id == 'date'), false);
    });

    test('respects the limit parameters when queried', () async {
      // 1. Insert 3 words with full coordinates (non-null embedding1bit)
      await database.wordsDao.insertEntities([
        Word(
          id: 'w1',
          spell: 'w1',
          popularity: 1,
          embedding1bit: Uint8List(256),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'w2',
          spell: 'w2',
          popularity: 1,
          embedding1bit: Uint8List(256),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'w3',
          spell: 'w3',
          popularity: 1,
          embedding1bit: Uint8List(256),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
      ]);

      // 2. Query with limit = 2
      final results = await database.wordsDao.getWordsWithCoordinates(limit: 2);

      // 3. Verify only 2 results are returned
      expect(results.length, 2);
    });
  });

  group('DictWordsDao - 删除路径 seq 连续性', () {
    const dictId = 'dict_seq_test';
    const userId = 'u1';

    setUp(() {
      // DbLogUtil.logOperation 依赖 MyDatabase.instance 单例，必须指向测试库才能写入日志
      MyDatabase.setInstanceForTesting(database);
    });

    Future<void> insertDict(int wordCount) async {
      final now = DateTime.now();
      await database.dictsDao.saveEntity(Dict(
        id: dictId,
        name: '测试词书',
        wordCount: wordCount,
        isShared: false,
        isReady: true,
        ownerId: userId,
        visible: true,
        editable: false,
        deletable: true,
        createTime: now,
        updateTime: now,
      ), false);
    }

    Future<void> insertWords(List<String> wordIds, List<int> seqs) async {
      final now = DateTime.now();
      await database.dictWordsDao.insertEntities([
        for (var i = 0; i < wordIds.length; i++)
          DictWord(
            dictId: dictId,
            wordId: wordIds[i],
            seq: seqs[i],
            unit: 0,
            createTime: now,
            updateTime: now,
          ),
      ], false);
    }

    Future<List<int>> seqs() async {
      final rows = await (database.select(database.dictWords)
            ..where((dw) => dw.dictId.equals(dictId))
            ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
          .get();
      return rows.map((r) => r.seq).toList();
    }

    Future<List<UserDbLog>> dictWordLogs({String? operate}) {
      final query = database.select(database.userDbLogs)
        ..where((l) => l.tblName.equals('dictWords') & l.recordId.like('$dictId-%'));
      if (operate != null) {
        query.where((l) => l.operate.equals(operate));
      }
      return query.get();
    }

    test('删除中间词后剩余 seq 连续，且生成前移 UPDATE 日志与 DELETE 日志', () async {
      await insertDict(5);
      await insertWords(['w1', 'w2', 'w3', 'w4', 'w5'], [1, 2, 3, 4, 5]);

      await database.dictWordsDao.deleteDictWordWithCleanup(dictId, 'w3', userId, true);

      // 剩余词 seq 连续为 1..4
      expect(await seqs(), [1, 2, 3, 4]);

      // 被前移的词 w4、w5 各生成一条 UPDATE 日志
      final updateLogs = await dictWordLogs(operate: 'UPDATE');
      expect(updateLogs.length, 2);
      expect(updateLogs.map((l) => l.recordId).toSet(), {'$dictId-w4', '$dictId-w5'});

      // 同时有 1 条 DELETE 日志
      final deleteLogs = await dictWordLogs(operate: 'DELETE');
      expect(deleteLogs.length, 1);
      expect(deleteLogs.single.recordId, '$dictId-w3');
    });

    test('genLog=false 删除不重排、不生成 UPDATE 日志', () async {
      await insertDict(5);
      await insertWords(['w1', 'w2', 'w3', 'w4', 'w5'], [1, 2, 3, 4, 5]);

      final w3 = await database.dictWordsDao.getById(dictId, 'w3');
      await database.dictWordsDao.deleteEntity(w3!, false);

      // seq 保持断裂，不重排
      expect(await seqs(), [1, 2, 4, 5]);
      expect(await dictWordLogs(operate: 'UPDATE'), isEmpty);
    });

    test('删除最后一个词不重排、无 UPDATE 日志，但有 DELETE 日志', () async {
      await insertDict(5);
      await insertWords(['w1', 'w2', 'w3', 'w4', 'w5'], [1, 2, 3, 4, 5]);

      await database.dictWordsDao.deleteDictWordWithCleanup(dictId, 'w5', userId, true);

      expect(await seqs(), [1, 2, 3, 4]);
      expect(await dictWordLogs(operate: 'UPDATE'), isEmpty);
      expect((await dictWordLogs(operate: 'DELETE')).length, 1);
    });

    test('断裂词书删除后自愈为从 1 开始的连续 seq', () async {
      await insertDict(3);
      // 模拟历史断裂：seq 从 3 开始
      await insertWords(['wa', 'wb', 'wc'], [3, 4, 5]);

      final wa = await database.dictWordsDao.getById(dictId, 'wa');
      await database.dictWordsDao.deleteEntity(wa!, true);

      expect(await seqs(), [1, 2]);
      expect((await dictWordLogs(operate: 'UPDATE')).length, 2);
    });

    test('删除后新加词续接为剩余最大 seq + 1', () async {
      await insertDict(5);
      await insertWords(['w1', 'w2', 'w3', 'w4', 'w5'], [1, 2, 3, 4, 5]);

      await database.dictWordsDao.deleteDictWordWithCleanup(dictId, 'w3', userId, true);
      expect(await seqs(), [1, 2, 3, 4]);

      final now = DateTime.now();
      await database.dictWordsDao.insertEntity(DictWord(
        dictId: dictId,
        wordId: 'w6',
        seq: 0,
        unit: 0,
        createTime: now,
        updateTime: now,
      ), true);

      expect(await seqs(), [1, 2, 3, 4, 5]);
      final w6 = await database.dictWordsDao.getById(dictId, 'w6');
      expect(w6!.seq, 5);
    });
  });
}
