import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/sync.dart';

/// 回归：老客户端（或服务端全量同步）写入的实体快照可能缺少后新增的字段，
/// 例如 learning_word 的 isExtra、book_mark 的 sortAlg。
/// 客户端必须按本地表结构的默认值补全这些字段，而不是抛
/// "type 'Null' is not a subtype of type 'bool'" 后跳过整条记录（静默丢失数据）。
void main() {
  late MyDatabase database;

  const userId = '6fbc161e841d4ed8820b1c727b4776f2';
  const wordId = '11278';

  setUp(() async {
    database = MyDatabase(DatabaseConnection(NativeDatabase.memory()));
    MyDatabase.setInstanceForTesting(database);
    await _insertDict(database, userId, '生词本');
    await _insertDict(database, userId, '已掌握');
  });

  tearDown(() async {
    await database.close();
  });

  UserDbLogDto backendLog(String remoteTable, String recordId, Map<String, dynamic> record) {
    final now = DateTime.now();
    return UserDbLogDto('log-$recordId', userId, 1, 'INSERT', remoteTable, recordId, jsonEncode(record), now, now);
  }

  test('缺少 isExtra 的 learning_word 日志：按表结构默认值 false 落库', () async {
    await doSyncUserDb([], [
      backendLog('learning_word', '$userId-$wordId', {
        'userId': userId,
        'wordId': wordId,
        'addDay': 1,
        'addTime': 1784146312000,
        'lastLearningDate': 1788624000000,
        'learningOrder': 0,
        'batchId': 0,
        // 老日志没有 isExtra
        'stability': 0.1,
        'difficulty': 10.0,
        'elapsedDays': 6,
        'scheduledDays': 1,
        'reps': 8,
        'lapses': 6,
        'state': 3,
        'isTodayNewWord': false,
        'learnedTimes': 16,
        'todayLearnedTimes': 0,
        'createTime': 1784146312000,
        'updateTime': 1788183110000,
      }),
    ], 1, userId);

    final saved = await database.learningWordsDao.getById(userId, wordId);
    expect(saved, isNotNull, reason: '缺少 isExtra 的日志不应被跳过');
    expect(saved!.isExtra, isFalse);
  });

  test('缺少 sortAlg 的 book_mark 日志：按表结构默认值 ORIGINAL 落库', () async {
    await doSyncUserDb([], [
      backendLog('book_mark', '1779007198405', {
        'id': '1779007198405',
        'userId': userId,
        'bookMarkName': 'today_words_list',
        'spell': 'heart',
        'position': 3,
        // 老日志没有 sortAlg
        'createTime': 1779007198000,
        'updateTime': 1779007200966,
      }),
    ], 1, userId);

    final saved = await (database.select(database.bookMarks)
          ..where((b) => b.id.equals('1779007198405')))
        .getSingleOrNull();
    expect(saved, isNotNull, reason: '缺少 sortAlg 的日志不应被跳过');
    expect(saved!.sortAlg, 'ORIGINAL');
  });
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
