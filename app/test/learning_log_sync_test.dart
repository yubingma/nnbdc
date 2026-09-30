import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/sync.dart';

/// 回归：学习记录（learning_log）从服务端下发到客户端时的三态落库。
///
/// 关键约定（见 app/lib/util/sync.dart:531）：DELETE 日志的 record 只带 `{'id': ...}`
/// （一次性修复为了不把单次同步请求撑爆而写的缩体格式），不能整体反序列化成 LearningLog；
/// 必须按 id 直接删本地行。若这段被改成 `LearningLog.fromJson`，会因缺少 userId/wordId 等
/// 字段直接抛错，导致别的设备永远收敛不掉被修复掉的重复计分日志。
void main() {
  late MyDatabase database;

  const userId = '6fbc161e841d4ed8820b1c727b4776f2';

  setUp(() async {
    database = MyDatabase(DatabaseConnection(NativeDatabase.memory()));
    MyDatabase.setInstanceForTesting(database);
    await _insertDict(database, userId, '生词本');
    await _insertDict(database, userId, '已掌握');
  });

  tearDown(() async {
    await database.close();
  });

  UserDbLogDto backendLog(String operate, String recordId, Map<String, dynamic> record) {
    final now = DateTime.now();
    return UserDbLogDto('log-$operate-$recordId', userId, 1, operate, 'learning_log',
        recordId, jsonEncode(record), now, now);
  }

  Map<String, dynamic> recordOf(String id, {double stability = 3.173}) => {
        'id': id,
        'userId': userId,
        'wordId': 'w_1',
        'rating': 3,
        'stability': stability,
        'difficulty': 5.0,
        'elapsedDays': 0,
        'scheduledDays': 3,
        'createTime': 1784146312000,
        'updateTime': 1784146312000,
      };

  test('DELETE（record 只有 id）：按 id 删掉本地行，且不写回同步日志', () async {
    await database.learningLogsDao.saveEntity(LearningLog(
      id: 'log_to_delete',
      userId: userId,
      wordId: 'w_1',
      rating: 3,
      stability: 3.173,
      difficulty: 5.0,
      elapsedDays: 0,
      scheduledDays: 3,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
    ), false);

    await doSyncUserDb([], [
      backendLog('DELETE', 'log_to_delete', {'id': 'log_to_delete'}),
    ], 1, userId);

    final remain =
        await (database.select(database.learningLogs)..where((l) => l.id.equals('log_to_delete')))
            .getSingleOrNull();
    expect(remain, isNull, reason: '缩体 DELETE 必须按 id 删掉本地学习记录，而不是抛反序列化错误');
    expect(await database.userDbLogsDao.getUserDbLogs(userId), isEmpty,
        reason: '服务端下发的删除不得在本地回声成新的待上传日志');
  });

  test('INSERT 与 UPDATE：按完整快照落库，且不写回同步日志', () async {
    await doSyncUserDb([], [
      backendLog('INSERT', 'log_1', recordOf('log_1')),
    ], 1, userId);

    var saved = await _findLog(database, 'log_1');
    expect(saved, isNotNull, reason: '服务端新增的学习记录必须落库');
    expect(saved!.stability, 3.173);

    await doSyncUserDb([], [
      backendLog('UPDATE', 'log_1', recordOf('log_1', stability: 8.5)),
    ], 2, userId);

    saved = await _findLog(database, 'log_1');
    expect(saved!.stability, 8.5, reason: '服务端修改的学习记录必须覆盖本地旧值');
    expect(await database.userDbLogsDao.getUserDbLogs(userId), isEmpty,
        reason: '服务端下发的新增/修改也不得在本地回声成新的待上传日志');
  });
}

Future<LearningLog?> _findLog(MyDatabase database, String id) {
  return (database.select(database.learningLogs)..where((l) => l.id.equals(id)))
      .getSingleOrNull();
}

Future<void> _insertDict(MyDatabase database, String userId, String name) async {
  final now = DateTime.now();
  await database.dictsDao.saveEntity(
    Dict(
      id: '$userId-$name',
      name: name,
      wordCount: 0,
      isShared: false,
      isReady: true,
      ownerId: userId,
      visible: true,
      editable: false,
      deletable: true,
      createTime: now,
      updateTime: now,
    ),
    false,
  );
}
