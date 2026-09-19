import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
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
