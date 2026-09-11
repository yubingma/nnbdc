import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/distractor_strategy.dart';

void main() {
  late MyDatabase db;
  final now = AppClock.now();
  const userId = 'distractor_test_user';

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    Global.clearUserCache();
  });

  tearDown(() async {
    await db.close();
    Global.clearUserCache();
  });

  Future<void> insertDict(String id) async {
    await db.into(db.dicts).insert(Dict(
          id: id,
          name: id,
          wordCount: 0,
          isShared: false,
          isReady: true,
          ownerId: userId,
          visible: true,
          editable: true,
          deletable: false,
          createTime: now,
          updateTime: now,
        ));
  }

  Future<void> insertLearningDict(String dictId) async {
    await db.into(db.learningDicts).insert(LearningDict(
          userId: userId,
          dictId: dictId,
          isPrivileged: false,
          fetchMastered: false,
          sortAlg: 'ORIGINAL',
          createTime: now,
          updateTime: now,
        ));
  }

  Future<void> insertWord(String id, String spell) async {
    await db.into(db.words).insert(Word(
          id: id,
          spell: spell,
          popularity: 1,
          createTime: now,
          updateTime: now,
        ));
  }

  Future<void> insertDictWord(String dictId, String wordId) async {
    await db.into(db.dictWords).insert(DictWord(
          dictId: dictId,
          wordId: wordId,
          seq: 1,
          unit: 0,
          createTime: now,
          updateTime: now,
        ));
  }

  /// 通用词典释义（dictId=0）：策略通过 WordBo.getWordMeaningItems 取候选词释义
  Future<void> insertMeaning(String wordId, String meaning) async {
    await db.into(db.meaningItems).insert(MeaningItem(
          id: 'mi_$wordId',
          wordId: wordId,
          dictId: Global.commonDictId,
          ciXing: 'vt.',
          meaning: meaning,
          popularity: 1,
          createTime: now,
          ownerId: '15118',
          updateTime: now,
        ));
  }

  Future<void> insertSimilar(String targetId, String similarId, String spell) async {
    await db.into(db.similarWords).insert(SimilarWord(
          wordId: targetId,
          similarWordId: similarId,
          similarWordSpell: spell,
          distance: 1,
          createTime: now,
          updateTime: now,
        ));
  }

  LearningWord targetLearningWord(String wordId) => LearningWord(
        userId: userId,
        wordId: wordId,
        addDay: 1,
        addTime: now,
        learningOrder: 1,
        isTodayNewWord: true,
        learnedTimes: 0,
        todayLearnedTimes: 0,
        createTime: now,
        updateTime: now,
      );

  List<MeaningItemVo> targetMeanings(String meaning) =>
      [MeaningItemVo('mi_target', 'vt.', meaning, null, null, null)];

  Future<List<WordVo>> pickDistractors(String targetWordId, String targetMeaning) {
    return ShapeSimilarDistractorStrategy().getTwoOtherWords(
      trackSteps: const ['En2Ch'],
      learningMode: 0,
      meaningItemVos: targetMeanings(targetMeaning),
      todayWords: const [],
      targetWordLearningData: targetLearningWord(targetWordId),
      db: db,
    );
  }

  group('ShapeSimilarDistractorStrategy - 形近词干扰项', () {
    test('非英译汉/汉译英环节不产生干扰项', () async {
      final words = await ShapeSimilarDistractorStrategy().getTwoOtherWords(
        trackSteps: const ['List'],
        learningMode: 0,
        meaningItemVos: targetMeanings('使困惑'),
        todayWords: const [],
        targetWordLearningData: targetLearningWord('w_confuse'),
        db: db,
      );
      expect(words, isEmpty);
    });

    test('同一单词的屈折变形（confused）不作为干扰项', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w_confuse', 'confuse');
      await insertWord('w_confused', 'confused');
      await insertWord('w_consume', 'consume');
      await insertWord('w_confess', 'confess');
      for (final id in ['w_confuse', 'w_confused', 'w_consume', 'w_confess']) {
        await insertDictWord('d1', id);
      }
      await insertSimilar('w_confuse', 'w_confused', 'confused');
      await insertSimilar('w_confuse', 'w_consume', 'consume');
      await insertSimilar('w_confuse', 'w_confess', 'confess');
      await insertMeaning('w_confuse', '使困惑');
      await insertMeaning('w_confused', '困惑的');
      await insertMeaning('w_consume', '消耗');
      await insertMeaning('w_confess', '坦白');

      final words = await pickDistractors('w_confuse', '使困惑');

      expect(words.map((w) => w.spell), isNot(contains('confused')));
      expect(words.map((w) => w.spell), containsAll(['consume', 'confess']));
    });

    test('释义与目标词完全相同的候选（confusion）不作为干扰项', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w_confuse', 'confuse');
      await insertWord('w_confusion', 'confusion');
      await insertWord('w_consume', 'consume');
      await insertWord('w_confess', 'confess');
      for (final id in ['w_confuse', 'w_confusion', 'w_consume', 'w_confess']) {
        await insertDictWord('d1', id);
      }
      await insertSimilar('w_confuse', 'w_confusion', 'confusion');
      await insertSimilar('w_confuse', 'w_consume', 'consume');
      await insertSimilar('w_confuse', 'w_confess', 'confess');
      await insertMeaning('w_confuse', '使困惑');
      await insertMeaning('w_confusion', '使困惑');
      await insertMeaning('w_consume', '消耗');
      await insertMeaning('w_confess', '坦白');

      final words = await pickDistractors('w_confuse', '使困惑');

      expect(words.map((w) => w.spell), isNot(contains('confusion')));
      expect(words.map((w) => w.spell), containsAll(['consume', 'confess']));
    });

    test('学习范围内的形近词优先，即使其前三字母与目标词相同', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w_confuse', 'confuse');
      await insertWord('w_confer', 'confer'); // 范围内，前缀与目标词相同
      await insertWord('w_infuse', 'infuse'); // 范围外，前缀不同
      await insertDictWord('d1', 'w_confuse');
      await insertDictWord('d1', 'w_confer');
      await insertSimilar('w_confuse', 'w_confer', 'confer');
      await insertSimilar('w_confuse', 'w_infuse', 'infuse');
      await insertMeaning('w_confuse', '使困惑');
      await insertMeaning('w_confer', '授予');
      await insertMeaning('w_infuse', '注入');

      final words = await pickDistractors('w_confuse', '使困惑');

      expect(words.first.spell, 'confer');
    });

    test('个别候选缺少释义时跳过该候选，不影响其余干扰项', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w_confuse', 'confuse');
      await insertWord('w_confute', 'confute'); // 故意不插释义
      await insertWord('w_consume', 'consume');
      await insertWord('w_confess', 'confess');
      for (final id in ['w_confuse', 'w_confute', 'w_consume', 'w_confess']) {
        await insertDictWord('d1', id);
      }
      await insertSimilar('w_confuse', 'w_confute', 'confute');
      await insertSimilar('w_confuse', 'w_consume', 'consume');
      await insertSimilar('w_confuse', 'w_confess', 'confess');
      await insertMeaning('w_confuse', '使困惑');
      await insertMeaning('w_consume', '消耗');
      await insertMeaning('w_confess', '坦白');

      final words = await pickDistractors('w_confuse', '使困惑');

      expect(words.map((w) => w.spell), isNot(contains('confute')));
      expect(words.map((w) => w.spell), containsAll(['consume', 'confess']));
    });

    test('没有任何学习词书时不做范围限制，仍能选出干扰项', () async {
      await insertWord('w_confuse', 'confuse');
      await insertWord('w_consume', 'consume');
      await insertWord('w_confess', 'confess');
      await insertSimilar('w_confuse', 'w_consume', 'consume');
      await insertSimilar('w_confuse', 'w_confess', 'confess');
      await insertMeaning('w_confuse', '使困惑');
      await insertMeaning('w_consume', '消耗');
      await insertMeaning('w_confess', '坦白');

      final words = await pickDistractors('w_confuse', '使困惑');

      expect(words.map((w) => w.spell), containsAll(['consume', 'confess']));
    });
  });
}
