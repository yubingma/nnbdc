import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/local_word_cache.dart';
import 'package:nnbdc/util/spell_normalize.dart';

void main() {
  late MyDatabase db;
  final now = DateTime(2026, 1, 1);

  Future<void> insertWord(String spell) async {
    await db.wordsDao.insertEntity(Word(
      id: spell,
      spell: spell,
      popularity: 1,
      createTime: now,
      updateTime: now,
    ));
  }

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    await insertWord('high-powered');
    await insertWord('high');
    await insertWord('high school');
    await insertWord('(be) at stake');
    await insertWord('7-Eleven');
    await insertWord("don't");
  });

  tearDown(() async {
    MyDatabase.setInstanceForTesting(null);
    await db.close();
  });

  group('SpellNormalize', () {
    test('归一化只删分隔符，不改变其余字符', () {
      expect(SpellNormalize.normalize('high-powered'), 'highpowered');
      expect(SpellNormalize.normalize('High Powered'), 'highpowered');
      expect(SpellNormalize.normalize('highpowered'), 'highpowered');
      expect(SpellNormalize.normalize("don't"), 'dont');
      expect(SpellNormalize.normalize('...'), '');
    });
  });

  group('查词列表的前缀匹配忽略分隔符', () {
    Future<List<String>> search(String query) async {
      final words = await LocalWordCache.instance.fuzzySearchWord(query);
      return words.map((w) => w.spell).toList();
    }

    test('highpowered 命中 high-powered', () async {
      expect(await search('highpowered'), contains('high-powered'));
    });

    test('high powered 命中 high-powered', () async {
      expect(await search('high powered'), contains('high-powered'));
    });

    test('字面拼写前缀照旧命中', () async {
      expect(await search('high'), containsAll(['high', 'high school', 'high-powered']));
      expect(await search('high s'), contains('high school'));
    });

    test('首字符不是字母的词条同样能被归一化命中', () async {
      expect(await search('beatstake'), contains('(be) at stake'));
      expect(await search('7eleven'), contains('7-Eleven'));
    });

    test('撇号省略也能命中', () async {
      expect(await search('dont'), contains("don't"));
    });

    test('匹配不上就是空结果', () async {
      expect(await search('zzzz'), isEmpty);
    });
  });

  group('精确查词忽略分隔符', () {
    test('highpowered / high powered / high-powered 都能查到 high-powered', () async {
      for (final query in ['highpowered', 'high powered', 'high-powered']) {
        final result = await WordBo().searchWordLocalOnly(query);
        expect(result.word?.spell, 'high-powered', reason: '查询：$query');
      }
    });

    test('查不到的词仍然返回空', () async {
      final result = await WordBo().searchWordLocalOnly('zzzz');
      expect(result.word, isNull);
    });
  });
}
