import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';

/// 本地同步日志「按 ID 批量删除」的测试。
///
/// 分批上传后，每批成功只能删掉这一批的日志行；
/// 若仍沿用「按用户整表删除」，会连带清掉还没上传的批次，造成数据丢失。
void main() {
  late MyDatabase database;

  setUp(() {
    database = MyDatabase(DatabaseConnection(NativeDatabase.memory()));
  });

  tearDown(() async {
    await database.close();
  });

  UserDbLog buildLog(String id, String userId) {
    final now = DateTime(2026, 10, 11, 9, 0, 0);
    return UserDbLog(
      id: id,
      operate: 'INSERT',
      recordId: id,
      record: '{"dictId":"dict-1","wordId":"$id"}',
      tblName: 'dict_word',
      userId: userId,
      version: 0,
      createTime: now,
      updateTime: now,
    );
  }

  group('UserDbLogsDao.deleteUserDbLogsByIds', () {
    test('只删指定 ID 的日志行，其它日志与其它用户不受影响', () async {
      await database.batch((batch) {
        batch.insertAll(database.userDbLogs, [
          buildLog('a', 'u1'),
          buildLog('b', 'u1'),
          buildLog('c', 'u1'),
          buildLog('d', 'u2'),
        ]);
      });

      await database.userDbLogsDao.deleteUserDbLogsByIds(['a', 'c']);

      expect(
        (await database.userDbLogsDao.getUserDbLogs('u1')).map((log) => log.id).toList(),
        ['b'],
      );
      expect(
        (await database.userDbLogsDao.getUserDbLogs('u2')).map((log) => log.id).toList(),
        ['d'],
      );
    });

    test('空清单不报错', () async {
      await database.into(database.userDbLogs).insert(buildLog('a', 'u1'));

      await database.userDbLogsDao.deleteUserDbLogsByIds(const []);

      expect(await database.userDbLogsDao.getUserDbLogs('u1'), hasLength(1));
    });

    test('条数超过单条 SQL 的参数规模时也能全部删除', () async {
      final ids = List.generate(900, (i) => 'log-$i');
      await database.batch((batch) {
        batch.insertAll(database.userDbLogs, ids.map((id) => buildLog(id, 'u1')).toList());
      });

      await database.userDbLogsDao.deleteUserDbLogsByIds(ids);

      expect(await database.userDbLogsDao.getUserDbLogs('u1'), isEmpty);
    });
  });
}
