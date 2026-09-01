import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/sync.dart';
import 'package:nnbdc/util/utils.dart';

void main() {
  late MyDatabase database;

  setUp(() {
    database = MyDatabase(DatabaseConnection(NativeDatabase.memory()));
    // DbLogUtil.logOperation 与 repairDictWordSequences 依赖 MyDatabase.instance 单例，
    // 必须指向测试库才能读写日志
    MyDatabase.setInstanceForTesting(database);
  });

  tearDown(() async {
    await database.close();
  });

  const userId = 'u1';
  const userDictId = 'user_dict';
  const sysDictId = 'sys_dict';
  // 系统词书 ownerId：系统用户 ID，用于区分非当前用户词书
  const sysUserId = Global.sysUserId;

  Future<void> insertDict(String dictId, String ownerId) async {
    final now = DateTime.now();
    await database.dictsDao.saveEntity(Dict(
      id: dictId,
      name: dictId == sysDictId ? '系统词书' : '用户词书',
      wordCount: 0,
      isShared: false,
      isReady: true,
      ownerId: ownerId,
      visible: true,
      editable: false,
      deletable: true,
      createTime: now,
      updateTime: now,
    ), false);
  }

  Future<void> insertWords(String dictId, List<String> wordIds, List<int> seqs) async {
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

  Future<List<int>> seqsOf(String dictId) async {
    final rows = await (database.select(database.dictWords)
          ..where((dw) => dw.dictId.equals(dictId))
          ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
        .get();
    return rows.map((r) => r.seq).toList();
  }

  Future<List<UserDbLog>> dictWordLogs({String? operate}) {
    final query = database.select(database.userDbLogs)
      ..where((l) => l.tblName.equals('dictWords'));
    if (operate != null) {
      query.where((l) => l.operate.equals(operate));
    }
    return query.get();
  }

  group('repairDictWordSequences - 同步前 seq 自检', () {
    test('用户词书 seq 断裂 [3,4,5] → 修复为 [1,2,3] 且生成 3 条 UPDATE 日志', () async {
      await insertDict(userDictId, userId);
      await insertWords(userDictId, ['wa', 'wb', 'wc'], [3, 4, 5]);

      await repairDictWordSequences(userId);

      expect(await seqsOf(userDictId), [1, 2, 3]);
      final updateLogs = await dictWordLogs(operate: 'UPDATE');
      expect(updateLogs.length, 3);
      expect(
        updateLogs.map((l) => l.recordId).toSet(),
        {'$userDictId-wa', '$userDictId-wb', '$userDictId-wc'},
      );
    });

    test('seq 连续词书 → 调用后零新日志', () async {
      await insertDict(userDictId, userId);
      await insertWords(userDictId, ['w1', 'w2', 'w3'], [1, 2, 3]);

      final before = await dictWordLogs();
      await repairDictWordSequences(userId);
      final after = await dictWordLogs();

      expect(after.length, before.length);
    });

    test('非用户词书（系统词书）seq 断裂 → 不被修复、无 UPDATE 日志', () async {
      await insertDict(userDictId, userId);
      await insertWords(userDictId, ['w1', 'w2', 'w3'], [1, 2, 3]);
      await insertDict(sysDictId, sysUserId);
      await insertWords(sysDictId, ['sa', 'sb'], [7, 8]);

      await repairDictWordSequences(userId);

      // 系统词书保持断裂，不被修复
      expect(await seqsOf(sysDictId), [7, 8]);
      // 用户词书连续、系统词书被跳过 → 无任何 dictWords UPDATE 日志
      expect(await dictWordLogs(operate: 'UPDATE'), isEmpty);
    });
  });

  group('repairInvalidBookMarkNames - 同步前超长书签名自检', () {
    Future<void> insertBookmark(String id, String bookMarkName) async {
      final now = DateTime.now();
      await database.bookmarksDao.saveBookmark(BookMark(
        id: id,
        userId: userId,
        bookMarkName: bookMarkName,
        spell: 'word',
        position: 0,
        sortAlg: 'ORIGINAL',
        createTime: now,
        updateTime: now,
      ), false);
    }

    Future<void> insertPendingLog(String recordId, String recordJson) async {
      final now = DateTime.now();
      await database.userDbLogsDao.insertEntity(UserDbLog(
        id: Util.uuid(),
        userId: userId,
        operate: 'INSERT',
        tblName: 'bookMarks',
        recordId: recordId,
        record: recordJson,
        version: 0,
        createTime: now,
        updateTime: now,
      ));
    }

    Future<List<BookMark>> bookmarksOf() async {
      return (database.select(database.bookMarks)..where((b) => b.userId.equals(userId))).get();
    }

    test('超长书签名坏数据被删除、正常书签保留、对应待同步日志被清除', () async {
      final validName = 'dict_9c4cd12b658e458db6ba6fbb3da3e3cf_words_list';
      final invalidName = 'dict_${'x' * 400}_words_list';

      // 一条正常书签 + 一条超长坏书签
      await insertBookmark('valid-bm', validName);
      await insertBookmark('invalid-bm', invalidName);

      // 为坏书签插入待同步日志，模拟其 pending 上传
      await insertPendingLog('invalid-bm', '{"bookMarkName":"$invalidName"}');
      // 正常书签的日志应保留
      await insertPendingLog('valid-bm', '{"bookMarkName":"$validName"}');

      await repairInvalidBookMarkNames(userId);

      final remaining = await bookmarksOf();
      expect(remaining.map((b) => b.id), ['valid-bm']);
      expect(remaining.single.bookMarkName, validName);

      final remainingLogs = await (database.select(database.userDbLogs)
            ..where((l) => l.tblName.equals('bookMarks')))
          .get();
      expect(remainingLogs.map((l) => l.recordId), ['valid-bm']);
    });

    test('无超长书签 → 不产生任何删除', () async {
      final validName = 'dict_9c4cd12b658e458db6ba6fbb3da3e3cf_words_list';
      await insertBookmark('valid-bm', validName);

      await repairInvalidBookMarkNames(userId);

      expect(await bookmarksOf(), hasLength(1));
    });
  });
}
