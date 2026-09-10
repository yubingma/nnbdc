import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/excel_import_parser.dart';
import 'package:nnbdc/util/xlsx_reader.dart';

void main() {
  group('XlsxReader', () {
    test('解析工作表名、共享字符串、数字单元格与空行', () {
      final bytes = File('test/fixtures/excel_import_sample.xlsx').readAsBytesSync();
      final sheet = XlsxReader.read(bytes);

      expect(sheet.name, '词表');
      expect(sheet.rows.length, 7);
      expect(sheet.rows[0], ['单词', '释义', '词性', '单元']);
      expect(sheet.rows[1], ['ability', 'n. 能力；才能', 'n.', '1']);
      // 缺失的 C 列补空串，数字单元格按原文读取
      expect(sheet.rows[3], ['algorithm', 'n. 算法', '', '2']);
      // 空行保留，由解析层负责跳过
      expect(sheet.rows[4].every((cell) => cell.isEmpty), isTrue);
      expect(sheet.rows[6], ['123abc 中文']);
    });

    test('非 xlsx 字节抛出 FormatException', () {
      expect(
        () => XlsxReader.read(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<FormatException>()),
      );
    });

    test('按 OLE2 文件头识别旧版 .xls', () {
      expect(
        XlsxReader.isLegacyXls(Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])),
        isTrue,
      );
      expect(
        XlsxReader.isLegacyXls(File('test/fixtures/excel_import_sample.xlsx').readAsBytesSync()),
        isFalse,
      );
    });
  });

  group('ExcelColumnDetector', () {
    test('按中文表头识别四列', () {
      final mapping = ExcelColumnDetector.detect([
        ['单词', '释义', '词性', '单元'],
        ['ability', 'n. 能力', 'n.', '1'],
      ]);

      expect(mapping.spellColumn, 0);
      expect(mapping.meaningColumn, 1);
      expect(mapping.partOfSpeechColumn, 2);
      expect(mapping.unitColumn, 3);
      expect(mapping.headerRowIndex, 0);
      expect(mapping.firstDataRowIndex, 1);
    });

    test('列顺序与英文表头都不影响识别', () {
      final mapping = ExcelColumnDetector.detect([
        ['meaning', 'word'],
        ['能力', 'ability'],
      ]);

      expect(mapping.spellColumn, 1);
      expect(mapping.meaningColumn, 0);
      expect(mapping.headerRowIndex, 0);
    });

    test('无表头时按列内容特征推断', () {
      final mapping = ExcelColumnDetector.detect([
        ['ability', 'n. 能力'],
        ['abandon', 'v. 放弃'],
        ['academic', 'adj. 学术的'],
      ]);

      expect(mapping.spellColumn, 0);
      expect(mapping.meaningColumn, 1);
      expect(mapping.headerRowIndex, isNull);
      expect(mapping.firstDataRowIndex, 0);
    });

    test('无法判断单词列时不猜测', () {
      final mapping = ExcelColumnDetector.detect([
        ['1', '2'],
        ['3', '4'],
      ]);

      expect(mapping.hasSpellColumn, isFalse);
    });
  });

  group('ExcelRowParser', () {
    test('剥离音标并保留合法拼写', () {
      final parsed = ExcelRowParser.parse(
        [
          ['ability [əˈbɪləti]', 'n. 能力'],
        ],
        const ExcelColumnMapping(spellColumn: 0, meaningColumn: 1),
      );

      expect(parsed.single.spell, 'ability');
      expect(parsed.single.status, ExcelRowStatus.ready);
    });

    test('释义中的中英文分号与换行统一为分号', () {
      final parsed = ExcelRowParser.parse(
        [
          ['ability', 'n. 能力；才能\n本领'],
        ],
        const ExcelColumnMapping(spellColumn: 0, meaningColumn: 1),
      );

      expect(parsed.single.meaning, 'n. 能力;才能;本领');
    });

    test('文件内重复的拼写合并释义并标记为重复', () {
      final parsed = ExcelRowParser.parse(
        [
          ['ability', 'n. 能力'],
          ['ABILITY', 'n. 能力；才能'],
        ],
        const ExcelColumnMapping(spellColumn: 0, meaningColumn: 1),
      );

      expect(parsed.length, 2);
      expect(parsed[0].spell, 'ability');
      expect(parsed[0].meaning, 'n. 能力;才能');
      expect(parsed[0].status, ExcelRowStatus.ready);
      expect(parsed[1].status, ExcelRowStatus.duplicate);
    });

    test('含中文或为空的拼写判为格式错误', () {
      final parsed = ExcelRowParser.parse(
        [
          ['能力', 'n. 能力'],
          ['   ', '孤立释义'],
        ],
        const ExcelColumnMapping(spellColumn: 0, meaningColumn: 1),
      );

      expect(parsed.every((row) => row.status == ExcelRowStatus.invalid), isTrue);
    });

    test('整行空白被跳过，单元列解析为序号', () {
      final parsed = ExcelRowParser.parse(
        [
          ['', ''],
          ['ability', 'n. 能力', 'n.', '3'],
        ],
        const ExcelColumnMapping(
          spellColumn: 0,
          meaningColumn: 1,
          partOfSpeechColumn: 2,
          unitColumn: 3,
        ),
      );

      expect(parsed.length, 1);
      expect(parsed.single.unit, 3);
      expect(parsed.single.partOfSpeech, 'n.');
      expect(parsed.single.lineNumber, 2);
    });

    test('跳过表头行', () {
      final parsed = ExcelRowParser.parse(
        [
          ['单词', '释义'],
          ['ability', 'n. 能力'],
        ],
        const ExcelColumnMapping(spellColumn: 0, meaningColumn: 1, headerRowIndex: 0),
      );

      expect(parsed.length, 1);
      expect(parsed.single.spell, 'ability');
    });

    test('词性列已给出词性时剥离释义中重复的前缀', () {
      final parsed = ExcelRowParser.parse(
        [
          ['ability', 'n. 能力；才能', 'n.'],
        ],
        const ExcelColumnMapping(spellColumn: 0, meaningColumn: 1, partOfSpeechColumn: 2),
      );

      expect(parsed.single.meaning, '能力;才能');
      expect(parsed.single.partOfSpeech, 'n.');
    });
  });

  group('WordBo.addWordsToCustomDict', () {
    late MyDatabase database;
    final now = DateTime.now();

    setUp(() {
      database = MyDatabase(NativeDatabase.memory());
      MyDatabase.setInstanceForTesting(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<void> seed() async {
      await database.into(database.dicts).insert(Dict(
            id: 'd1',
            isReady: true,
            isShared: false,
            name: '测试词书',
            wordCount: 0,
            ownerId: 'u1',
            visible: true,
            editable: true,
            deletable: true,
            createTime: now,
            updateTime: now,
          ));
      for (final entry in {'w1': 'ability', 'w2': 'abandon', 'w3': 'academic'}.entries) {
        await database.into(database.words).insert(Word(
              id: entry.key,
              popularity: 1,
              spell: entry.value,
              createTime: now,
              updateTime: now,
            ));
      }
    }

    Future<List<DictWord>> entriesOf(String dictId) async {
      final rows = await (database.select(database.dictWords)..where((t) => t.dictId.equals(dictId))).get();
      rows.sort((a, b) => a.seq.compareTo(b.seq));
      return rows;
    }

    Future<List<MeaningItem>> meaningsOf(String dictId) {
      return (database.select(database.meaningItems)..where((mi) => mi.dictId.equals(dictId))).get();
    }

    test('按行序写入连续 seq、写入定制释义并更新 wordCount', () async {
      await seed();

      final result = await WordBo().addWordsToCustomDict('d1', const [
        DictWordImportItem(wordId: 'w1', unit: 1, meaning: '能力;才能', partOfSpeech: 'n.'),
        DictWordImportItem(wordId: 'w2', unit: 1, meaning: '放弃'),
        DictWordImportItem(wordId: 'w3', unit: 2),
      ]);

      expect(result.success, isTrue);
      expect(result.data!.inserted, 3);
      expect(result.data!.updated, 0, reason: '全部是新词，不应计入「更新释义」');

      final entries = await entriesOf('d1');
      expect(entries.map((e) => e.wordId).toList(), ['w1', 'w2', 'w3']);
      expect(entries.map((e) => e.seq).toList(), [1, 2, 3]);
      expect(entries.map((e) => e.unit).toList(), [1, 1, 2]);

      final meanings = await meaningsOf('d1');
      expect(meanings.map((m) => m.meaning).toSet(), {'能力', '才能', '放弃'});
      expect(meanings.every((m) => m.ownerId == 'u1'), isTrue);

      final dict = await database.dictsDao.findById('d1');
      expect(dict!.wordCount, 3);
    });

    test('已在词表中的单词被跳过，不产生重复行', () async {
      await seed();
      await WordBo().addWordsToCustomDict('d1', const [DictWordImportItem(wordId: 'w1')]);

      final second = await WordBo().addWordsToCustomDict('d1', const [
        DictWordImportItem(wordId: 'w1'),
        DictWordImportItem(wordId: 'w2'),
      ]);

      expect(second.data!.inserted, 1);
      expect(second.data!.updated, 0, reason: '未开启更新且已存在词无释义，不应计入更新');
      expect((await entriesOf('d1')).length, 2);
    });

    test('updateMeanings 为 false 时不覆盖已有释义，为 true 时覆盖', () async {
      await seed();
      await WordBo().addWordsToCustomDict('d1', const [DictWordImportItem(wordId: 'w1', meaning: '旧释义')]);

      await WordBo().addWordsToCustomDict(
        'd1',
        const [DictWordImportItem(wordId: 'w1', meaning: '新释义')],
        updateMeanings: false,
      );
      expect((await meaningsOf('d1')).map((m) => m.meaning).toList(), ['旧释义']);

      final refreshed = await WordBo().addWordsToCustomDict(
        'd1',
        const [DictWordImportItem(wordId: 'w1', meaning: '新释义')],
        updateMeanings: true,
      );
      expect((await meaningsOf('d1')).map((m) => m.meaning).toList(), ['新释义']);
      // 已存在词被更新时应计入 updated 而非 inserted，否则结果页会错报成「已全部跳过」
      expect(refreshed.data!.updated, 1);
      expect(refreshed.data!.inserted, 0);
    });

    test('续接已有词表的最大 seq', () async {
      await seed();
      await database.into(database.dictWords).insert(DictWord(
            dictId: 'd1',
            wordId: 'w9',
            seq: 7,
            unit: 0,
            createTime: now,
            updateTime: now,
          ));

      await WordBo().addWordsToCustomDict('d1', const [DictWordImportItem(wordId: 'w1')]);

      final entry = await database.dictWordsDao.getById('d1', 'w1');
      expect(entry!.seq, 8);
    });

    test('matchWordIdsBySpells 支持大小写与词形变体', () async {
      await seed();
      await database.into(database.words).insert(Word(
            id: 'w4',
            popularity: 1,
            spell: 'study',
            createTime: now,
            updateTime: now,
          ));

      final hits = await WordBo().matchWordIdsBySpells(['ability', 'ABILITY', 'studies', 'unknown']);

      expect(hits['ability'], 'w1');
      expect(hits['studies'], 'w4');
      expect(hits.containsKey('unknown'), isFalse);
    });
  });
}
