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

    test('通用词典存在多义项时，例句严格按 popularity 排序，不受底层例句 ID 大小干扰（如 abandon 狂热 vs 放弃）', () async {
      // 单词 abandon
      await database.into(database.words).insert(Word(
            id: 'w_abandon',
            popularity: 1,
            spell: 'abandon',
            createTime: now,
            updateTime: now,
          ));

      // 释义1：高频常用义项 (放弃, popularity=1)
      await database.into(database.meaningItems).insert(MeaningItem(
            id: 'mi_fangqi',
            wordId: 'w_abandon',
            dictId: Global.commonDictId,
            ciXing: 'v.',
            meaning: '放弃',
            popularity: 1,
            ownerId: Global.sysUserId,
            createTime: now,
            updateTime: now,
          ));
      // 释义2：冷门低频义项 (狂热, popularity=3)
      await database.into(database.meaningItems).insert(MeaningItem(
            id: 'mi_kuangre',
            wordId: 'w_abandon',
            dictId: Global.commonDictId,
            ciXing: 'n.',
            meaning: '狂热',
            popularity: 3,
            ownerId: Global.sysUserId,
            createTime: now,
            updateTime: now,
          ));

      // 模拟生产数据库：狂热的例句 ID (520563) 比 放弃的例句 ID (530918) 小
      await database.into(database.sentences).insert(Sentence(
            id: '520563',
            english: 'His abandon in pursuing his goals was both admirable and concerning.',
            chinese: '他追求目标时的狂热既令人钦佩又令人担忧。',
            englishDigest: 'abandon',
            theType: 'tts',
            handCount: 0,
            footCount: 0,
            authorId: Global.sysUserId,
            ownerId: Global.sysUserId,
            meaningItemId: 'mi_kuangre',
            wordMeaning: '狂热',
            createTime: now,
            updateTime: now,
          ));
      await database.into(database.sentences).insert(Sentence(
            id: '530918',
            english: 'After several failed attempts, the team had to abandon their project.',
            chinese: '几次尝试失败后，团队不得不放弃他们的项目。',
            englishDigest: 'abandon',
            theType: 'tts',
            handCount: 0,
            footCount: 0,
            authorId: Global.sysUserId,
            ownerId: Global.sysUserId,
            meaningItemId: 'mi_fangqi',
            wordMeaning: '放弃',
            createTime: now,
            updateTime: now,
          ));

      // 1. 无偏好时，必须按 popularity 排序（放弃 popularity=1 优先于 狂热 popularity=3）
      final sentences = await database.sentencesDao.findCommonDictSentences('w_abandon');
      expect(sentences.first.id, '530918');
      expect(sentences.first.wordMeaning, '放弃');

      // 2. 自定义释义为 "v. 放弃" 时，语义优先匹配到 "放弃" 例句
      final customFangqi = MeaningItemVo('mi_custom_fq', 'v.', '放弃', null, null, null);
      await database.into(database.meaningItems).insert(MeaningItem(
            id: 'mi_custom_fq',
            wordId: 'w_abandon',
            dictId: 'custom_dict',
            ciXing: 'v.',
            meaning: '放弃',
            popularity: 1,
            ownerId: 'u1',
            createTime: now,
            updateTime: now,
          ));
      final fallbackForFangqi = await customFangqi.getSentences();
      expect(fallbackForFangqi.first.id, '530918');
      expect(fallbackForFangqi.first.wordMeaning, '放弃');

      // 3. 自定义释义为 "n. 狂热" 时，语义优先匹配到 "狂热" 例句
      final customKuangre = MeaningItemVo('mi_custom_kr', 'n.', '狂热', null, null, null);
      await database.into(database.meaningItems).insert(MeaningItem(
            id: 'mi_custom_kr',
            wordId: 'w_abandon',
            dictId: 'custom_dict',
            ciXing: 'n.',
            meaning: '狂热',
            popularity: 1,
            ownerId: 'u1',
            createTime: now,
            updateTime: now,
          ));
      final fallbackForKuangre = await customKuangre.getSentences();
      expect(fallbackForKuangre.first.id, '520563');
      expect(fallbackForKuangre.first.wordMeaning, '狂热');
    });
  });
}
