import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/sys_db_sync.dart';

/// 「深度讲解」中文译文（服务端 word.short_desc_cn）的端云同步回归：
/// 服务端 word 行新增该列后，客户端必须能把它落到本地 words 表，
/// 并在构造 WordVo 时带出（单词详情页据此展示译文）。
void main() {
  late MyDatabase database;

  const wordId = 'w-defect';
  const english = 'A flaw in something is a defect.';
  const chinese = '某物上的瑕疵就是 defect（缺陷）。';

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

  test('word UPDATE 日志带 shortDescCn：译文入库，且词向量不被刷空', () async {
    final embedding = base64Encode([1, 2, 3, 4]);
    await database.into(database.words).insert(WordsCompanion.insert(
          id: wordId,
          spell: 'defect',
          popularity: 5,
          shortDesc: const Value(english),
          createTime: DateTime.now(),
        ));

    await applySysDbLogs([
      log(
        'UPDATE',
        'word',
        wordId,
        '{"id":"$wordId","spell":"defect","popularity":5,'
            '"shortDesc":"$english","shortDescCn":"$chinese","embedding1bit":"$embedding"}',
      ),
    ]);

    final word = await (database.select(database.words)..where((w) => w.id.equals(wordId))).getSingle();
    expect(word.shortDescCn, chinese);
    expect(word.embedding1bit, [1, 2, 3, 4], reason: 'word 日志按整行覆盖，向量必须一起带下来');
  });

  test('WordVo 能从服务端 JSON 解析出 shortDescCn（详情页展示依据）', () {
    final vo = WordVo.fromJson({
      'id': wordId,
      'spell': 'defect',
      'popularity': 5,
      'shortDesc': english,
      'shortDescCn': chinese,
    });

    expect(vo.shortDesc, english);
    expect(vo.shortDescCn, chinese);
  });

  /// 生产库 sys_db_log 里真实下发的 word 记录（2026-09-27 abbot 一条），
  /// 用于锁住「服务端真实 payload 形态 → 客户端入库」这条链路：
  /// 含数字时间戳、longDesc 中的转义引号、以及 sound/phrase 等客户端不认识的字段。
  test('生产真实 word 日志能被客户端完整应用（含数字时间戳与未知字段）', () async {
    await applySysDbLogs([
      log('UPDATE', 'word', '3643', _prodAbbotRecord),
    ]);

    final word = await (database.select(database.words)..where((w) => w.id.equals('3643'))).getSingle();

    expect(word.spell, 'abbot');
    expect(word.shortDesc, startsWith('An abbot is the head of a monastery.'));
    expect(word.shortDescCn, 'abbot（男修道院院长）是修道院的首领。正如企业有老板、球队有教练一样，修道院有 abbot。');
    expect(word.embedding1bit, isNotNull);
    expect(word.embedding1bit!.length, 256, reason: '整行下发必须带回 256 字节词向量');
    expect(word.popularity, 0);
  });
}

/// 生产库原始记录（逐字拷贝，勿手改）
const String _prodAbbotRecord = r'''
{"createTime":1445951650000,"updateTime":1790519045438,"id":"3643","spell":"abbot","britishPronounce":"ˈæbət","americaPronounce":"ˈæbət","pronounce":"","popularity":0,"groupInfo":"","shortDesc":"An abbot is the head of a monastery. Just as businesses have bosses and teams have coaches, the monastery has an abbot.","shortDescCn":"abbot（男修道院院长）是修道院的首领。正如企业有老板、球队有教练一样，修道院有 abbot。","longDesc":"The word abbot comes from the Greek abbas, which means \"father” as a title with honor. An abbot is the superior of a monastery, the father of the fathers — in other words. Other monks must obey the abbot, and the abbot should lead and inspire all the monks.","embedding1bit":"YWqwCR4nBZ4T2X9fSsLd4U8Thkr4GrYMB7pjNv0J9ANP0ZhGjEHOYwq2/bv5iQ2enntKHPVEdFbKHTO94aaQaf9hk/rj7aAS6nwdOK5aFWU01SPIZWspWYSoakiSa1dml1COZQlKFupF/8viM0MHVkpCo/28GayO0fsFNDozL+UD9xYrL1ERqc9JaLKjIapJwWLV5/ZPWkGil08dSgr4Z4er5AYxgLszE9jFvfUpKUgENvpa2mYw0c1l8gtI9T8k8ArsEvyQqp7Ymd6eF3q5H2z+CekIV5aJVc/y9KDhVqGn/OFsNe5jcI1PNDnz9sASMVhofDyGS57d3AYiGNgsZQ==","ownerId":"15118","sound":"a/abbot","phrase":false}
''';
