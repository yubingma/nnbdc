import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/word_list/dict_words.dart';

void main() {
  late MyDatabase database;

  setUp(() {
    database = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('DictWordsProvider - hasUnits Test', () {
    test('returns false when no words have unit > 0', () async {
      final dict = DictVo(id: 'test_dict', name: 'Test Dict');
      final provider = DictWordsProvider(dict);

      // Insert word with unit = 0
      await database.into(database.dictWords).insert(DictWord(
        dictId: 'test_dict',
        wordId: 'w1',
        seq: 1,
        unit: 0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ));

      final hasUnits = await provider.hasUnits;
      expect(hasUnits, false);
    });

    test('returns true when at least one word has unit > 0', () async {
      final dict = DictVo(id: 'test_dict', name: 'Test Dict');
      final provider = DictWordsProvider(dict);

      // Insert word with unit = 1
      await database.into(database.dictWords).insert(DictWord(
        dictId: 'test_dict',
        wordId: 'w1',
        seq: 1,
        unit: 1,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ));

      final hasUnits = await provider.hasUnits;
      expect(hasUnits, true);
    });
  });
}
