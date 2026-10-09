import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/sync.dart';
import 'package:nnbdc/util/sys_db_sync.dart';
import 'package:nnbdc/util/utils.dart';

/// 回归：老客户端遇到不认识的后端表，绝不能中断整次同步，而应只跳过这张表；
/// 升级后（本客户端认识了这张表）又能凭「本地表为空」把当年跳过的数据点名补回来。
///
/// 线上真实事故：服务端下发 word_phrase / user_pet_state 日志，老包在
/// Util.remoteTableNameToLocal 上抛「不支持的后端表名」异常，整次同步（含用户数据）直接失败。
void main() {
  group('表名映射', () {
    test('不认识的后端表返回 null，而不是抛异常', () {
      expect(Util.remoteTableNameToLocal('game_hall'), isNull);
      expect(Util.remoteTableNameToLocal('word_phrase'), 'wordPhrases');
      expect(Util.remoteTableNameToLocal('user_pet_state'), 'userPetStates');
    });

    test('支持表清单来自映射表，且不含忽略标记', () {
      final supported = Util.supportedRemoteTableNames;
      expect(supported, contains('word_phrase'));
      expect(supported, contains('user_pet_state'));
      expect(supported, isNot(contains('word_shortdesc_chinese')));
      expect(supported, isNot(contains('users')), reason: 'users 只是历史兼容别名，不是真实后端表名');
    });
  });

  group('本地缺表探测', () {
    late MyDatabase database;

    setUp(() async {
      database = MyDatabase(DatabaseConnection(NativeDatabase.memory()));
      MyDatabase.setInstanceForTesting(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('空库时点名所有可整表补拉的表，且都必须在支持清单里', () async {
      final missingSystem = await findMissingSystemTables();
      final missingUser = await findMissingUserTables();

      expect(missingSystem, contains('word_core_image'));
      expect(missingSystem, contains('word_phrase'));
      expect(missingUser, contains('user_pet_state'));
      expect(missingUser, contains('user_badge'));

      final supported = Util.supportedRemoteTableNames;
      for (final table in [...missingSystem, ...missingUser]) {
        expect(supported, contains(table), reason: '$table 不在客户端的表名映射里，点名补拉必然无效');
      }
    });

    test('本地已有数据的表不再点名补拉', () async {
      await database.into(database.wordPhrases).insert(WordPhrasesCompanion.insert(
            id: 'wp1',
            wordId: 'w1',
            phrase: 'take off',
            source: 'collins',
          ));
      await database.into(database.userPetStates).insert(UserPetStatesCompanion.insert(
            id: 'ps1',
            userId: 'u1',
          ));

      expect(await findMissingSystemTables(), isNot(contains('word_phrase')));
      expect(await findMissingUserTables(), isNot(contains('user_pet_state')));
    });
  });

  group('应用系统数据日志', () {
    late MyDatabase database;

    setUp(() async {
      database = MyDatabase(DatabaseConnection(NativeDatabase.memory()));
      MyDatabase.setInstanceForTesting(database);
    });

    tearDown(() async {
      await database.close();
    });

    SysDbLogDto log(String tbl, String recordId, String record) {
      final now = AppClock.now();
      return SysDbLogDto('log-$tbl-$recordId', 1, 'INSERT', tbl, recordId, record, now, now);
    }

    test('遇到不认识的后端表：跳过它，同批次其它表照常同步', () async {
      await applySysDbLogs([
        log('game_hall', 'gh1', '{"id":"gh1"}'),
        log('word_phrase', 'wp2',
            '{"id":"wp2","wordId":"w1","phrase":"look up","source":"collins","displayIndex":0}'),
      ]);

      final phrases = await database.select(database.wordPhrases).get();
      expect(phrases.map((p) => p.id), contains('wp2'),
          reason: '同一批次里认识的表必须照常落库，不能被陌生表带崩');
    });
  });
}
