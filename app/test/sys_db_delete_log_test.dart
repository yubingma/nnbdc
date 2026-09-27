import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/sys_db_sync.dart';

/// 回归：系统数据 DELETE 日志的 record 为空（服务端历史日志即如此，
/// 删除只靠 recordId 定位目标）时，不得对它做 jsonDecode —— 否则抛
/// FormatException，整条删除被静默跳过，客户端残留已删除的关联数据，
/// 而版本号照常推进，导致该删除永久不再重试。
void main() {
  late MyDatabase database;

  const cigenId = 'facere_facio';
  const wordId = '10086';

  setUp(() async {
    database = MyDatabase(DatabaseConnection(NativeDatabase.memory()));
    MyDatabase.setInstanceForTesting(database);
  });

  tearDown(() async {
    await database.close();
  });

  SysDbLogDto log(String operate, String tbl, String recordId, String record) {
    final now = DateTime.now();
    return SysDbLogDto('log-$tbl-$recordId', 1, operate, tbl, recordId, record, now, now);
  }

  Future<void> seedLinkedWord() async {
    final now = DateTime.now();
    await database.into(database.cigens).insert(CigensCompanion.insert(
          id: cigenId,
          description: 'facere=do，表示“做”',
          createTime: now,
          spell: const Value('facere'),
          meaningCn: const Value('做'),
        ));
    await database.into(database.cigenWordLinks).insert(CigenWordLinksCompanion.insert(
          cigenId: cigenId,
          wordId: wordId,
          theExplain: 'facere 做 → 做',
          createTime: now,
        ));
  }

  test('DELETE 日志 record 为空串：仍能正常删除关联（不得跳过）', () async {
    await seedLinkedWord();

    await applySysDbLogs([
      log('DELETE', 'cigen_word_link', '${cigenId}_$wordId', ''),
    ]);

    final left = await database.select(database.cigenWordLinks).get();
    expect(left, isEmpty, reason: 'record 为空的 DELETE 日志必须照常执行删除');
  });

  test('DELETE 日志 record 为 {} ：正常删除词根主表记录', () async {
    await seedLinkedWord();

    await applySysDbLogs([
      log('DELETE', 'cigen_word_link', '${cigenId}_$wordId', '{}'),
      log('DELETE', 'cigen', cigenId, '{}'),
    ]);

    expect(await database.select(database.cigenWordLinks).get(), isEmpty);
    expect(await database.select(database.cigens).get(), isEmpty);
  });

  test('DELETE 日志 record 为 null 值文本：同样不得抛错跳过', () async {
    await seedLinkedWord();

    await applySysDbLogs([
      log('DELETE', 'cigen_word_link', '${cigenId}_$wordId', 'null'),
    ]);

    expect(await database.select(database.cigenWordLinks).get(), isEmpty);
  });
}
