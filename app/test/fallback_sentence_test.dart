import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';

void main() {
  late MyDatabase database;
  final now = DateTime.now();

  setUp(() {
    database = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(database);
  });

  tearDown(() async {
    await database.close();
  });

  /// 单词 ability：通用词典的释义带例句，用户自定义释义没有例句。
  Future<void> seed() async {
    await database.into(database.words).insert(Word(
          id: 'w1',
          popularity: 1,
          spell: 'ability',
          createTime: now,
          updateTime: now,
        ));

    await database.into(database.meaningItems).insert(MeaningItem(
          id: 'mi_common',
          wordId: 'w1',
          dictId: Global.commonDictId,
          ciXing: 'n.',
          meaning: '能力',
          popularity: 1,
          ownerId: Global.sysUserId,
          createTime: now,
          updateTime: now,
        ));
    await database.into(database.sentences).insert(Sentence(
          id: 's1',
          english: 'He has the ability to lead.',
          chinese: '他有领导能力。',
          englishDigest: 'ability',
          theType: 'tts',
          handCount: 0,
          footCount: 0,
          authorId: Global.sysUserId,
          ownerId: Global.sysUserId,
          meaningItemId: 'mi_common',
          wordMeaning: '能力',
          createTime: now,
          updateTime: now,
        ));

    await database.into(database.meaningItems).insert(MeaningItem(
          id: 'mi_custom',
          wordId: 'w1',
          dictId: 'custom_dict',
          ciXing: 'n.',
          meaning: '能力；才能',
          popularity: 1,
          ownerId: 'u1',
          createTime: now,
          updateTime: now,
        ));
  }

  group('自定义释义的例句兜底', () {
    test('自定义释义没有例句时，借通用词典同词的例句并标记 isFallback', () async {
      await seed();
      final meaningItem = MeaningItemVo('mi_custom', 'n.', '能力；才能', null, null, null);

      final sentences = await meaningItem.getSentences();

      expect(sentences.length, 1);
      expect(sentences.first.english, 'He has the ability to lead.');
      expect(sentences.first.isFallback, isTrue, reason: '兜底例句必须带标记，便于 UI 区分与排查');
    });

    test('通用词典释义取到自己的例句时不标记为兜底', () async {
      await seed();
      final meaningItem = MeaningItemVo('mi_common', 'n.', '能力', null, null, null);

      final sentences = await meaningItem.getSentences();

      expect(sentences.length, 1);
      expect(sentences.first.isFallback, isFalse);
    });

    test('通用词典也没有例句时返回空，不虚构也不误标', () async {
      await database.into(database.words).insert(Word(
            id: 'w2',
            popularity: 1,
            spell: 'uncovered',
            createTime: now,
            updateTime: now,
          ));
      await database.into(database.meaningItems).insert(MeaningItem(
            id: 'mi_none',
            wordId: 'w2',
            dictId: 'custom_dict',
            ciXing: 'n.',
            meaning: '无例句',
            popularity: 1,
            ownerId: 'u1',
            createTime: now,
            updateTime: now,
          ));

      final sentences = await MeaningItemVo('mi_none', 'n.', '无例句', null, null, null).getSentences();

      expect(sentences, isEmpty);
    });

    test('findCommonDictSentences 只返回通用词典的例句', () async {
      await seed();

      final sentences = await database.sentencesDao.findCommonDictSentences('w1');

      expect(sentences.map((s) => s.id).toList(), ['s1']);
    });
  });
}
