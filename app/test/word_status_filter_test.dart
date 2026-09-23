import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/word_status_filter.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_list/dict_words.dart';
import 'package:nnbdc/util/app_clock.dart';

void main() {
  late MyDatabase db;
  final now = AppClock.now();
  const userId = 'status_filter_test_user';

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    Global.clearUserCache();
  });

  tearDown(() async {
    await db.close();
    Global.clearUserCache();
  });

  group('WordStatusFilter 值类型', () {
    test('默认全选：不裁剪任何单词', () {
      expect(WordStatusFilter.all.isAll, isTrue);
      expect(WordStatusFilter.all.label, '全部');
      expect(WordStatusFilter.all.statuses.length, WordLearningStatus.values.length);
    });

    test('切换勾选；取消最后一项自动回落到全选', () {
      var filter = WordStatusFilter.all;

      filter = filter.toggle(WordLearningStatus.mastered);
      expect(filter.contains(WordLearningStatus.mastered), isFalse);
      expect(filter.label, '未学习+学习中');

      filter = filter.toggle(WordLearningStatus.learning);
      expect(filter.label, '未学习');

      // 取消最后一项 → 回落全选，用户不会被关进空列表
      filter = filter.toggle(WordLearningStatus.unlearned);
      expect(filter.isAll, isTrue);
    });

    test('编码往返稳定，且无法识别的编码回落全选', () {
      final filter = WordStatusFilter.all
          .toggle(WordLearningStatus.mastered)
          .toggle(WordLearningStatus.unlearned);
      expect(filter.code, 'LEARNING');
      expect(WordStatusFilter.fromCode(filter.code), filter);

      expect(WordStatusFilter.fromCode(null).isAll, isTrue);
      expect(WordStatusFilter.fromCode('').isAll, isTrue);
      expect(WordStatusFilter.fromCode('BOGUS').isAll, isTrue);
      expect(WordStatusFilter.fromCode('UNLEARNED,LEARNING,MASTERED').isAll, isTrue);
    });

    test('allows 把 null/false/true 三态映射到对应状态', () {
      final unlearnedOnly = WordStatusFilter.all
          .toggle(WordLearningStatus.learning)
          .toggle(WordLearningStatus.mastered);

      expect(unlearnedOnly.allows(null), isTrue);
      expect(unlearnedOnly.allows(false), isFalse);
      expect(unlearnedOnly.allows(true), isFalse);
      expect(WordStatusFilter.all.allows(null), isTrue);
      expect(WordStatusFilter.all.allows(false), isTrue);
      expect(WordStatusFilter.all.allows(true), isTrue);
    });

    test('三态数量：总数恒等于三者之和', () {
      const counts = WordStatusCounts(unlearned: 12, learning: 3, mastered: 5);
      expect(counts.total, 20);
      expect(counts.countOf(WordLearningStatus.unlearned), 12);
      expect(counts.countOf(WordLearningStatus.learning), 3);
      expect(counts.countOf(WordLearningStatus.mastered), 5);
    });
  });

  group('词表筛选偏好持久化（按词书分别记忆）', () {
    test('保存后可用新实例读回；换词书互不影响', () async {
      final dictA = _dictVo('dict_a');
      final dictB = _dictVo('dict_b');

      await DictWordsProvider(dictA).saveStatusFilter(
        WordStatusFilter.all.toggle(WordLearningStatus.mastered),
      );

      expect(await DictWordsProvider(dictA).getStatusFilter(),
          WordStatusFilter.all.toggle(WordLearningStatus.mastered));
      expect((await DictWordsProvider(dictB).getStatusFilter()).isAll, isTrue);
    });

    test('未保存过的词书默认全选', () async {
      expect((await DictWordsProvider(_dictVo('dict_none')).getStatusFilter()).isAll, isTrue);
    });
  });

  group('词书三态筛选（SQL 下推）', () {
    /// 五个单词覆盖三态与边界：
    /// w1 未学习 / w2 学习中(有记录) / w3 已掌握(在「已掌握」词书) /
    /// w4 有学习记录但稳定性已过毕业阈值且不在已掌握词书 → 按现有口径算"未学习" /
    /// w5 学习中(记录存在但未评分)
    Future<void> seed() async {
      await db.into(db.users).insert(User(
            id: userId,
            userName: 'mock_user',
            password: '',
            nickName: 'Tester',
            email: '',
            gameScore: 0,
            dakaScore: 0,
            learnedDays: 0,
            learningFinished: false,
            inviteAwardTaken: false,
            isSuperAdmin: false,
            isAdmin: false,
            isInputor: true,
            cowDung: 0,
            throwDiceChance: 0,
            wordsPerDay: 5,
            dakaDayCount: 0,
            masteredWordsCount: 0,
            maxContinuousDakaDayCount: 0,
            continuousDakaDayCount: 0,
            todayStudyStarted: false,
            totalLearningSeconds: 0,
            todayLearningSeconds: 0,
            createTime: now,
            updateTime: now,
          ));
      Global.currentUserId = userId;

      await _insertDict(db, now, 'dict_main', '主词书', userId);
      await _insertDict(db, now, 'dict_mastered', '已掌握', userId);

      const spells = ['zebra', 'bear', 'cat', 'ant', 'dog'];
      for (var i = 0; i < spells.length; i++) {
        final wordId = 'w${i + 1}';
        await _insertWord(db, now, wordId, spells[i]);
        await _insertDictWord(db, now, 'dict_main', wordId, seq: i + 1);
      }
      await _insertDictWord(db, now, 'dict_mastered', 'w3', seq: 1);

      await _insertLearningWord(db, now, userId, 'w2', stability: 10);
      await _insertLearningWord(db, now, userId, 'w4', stability: 200);
      await _insertLearningWord(db, now, userId, 'w5', stability: null);
    }

    setUp(seed);

    Future<List<String>> pageSpells(WordStatusFilter filter, {String? sortAlg}) async {
      final page = await WordBo().getDictWordsForAPage('dict_main', 0, 100,
          sortAlg: sortAlg, statusFilter: filter, userId: userId);
      return page.rows.map((row) => row.word.spell).toList();
    }

    Future<int> totalOf(WordStatusFilter filter) async {
      final page = await WordBo().getDictWordsForAPage('dict_main', 0, 100,
          statusFilter: filter, userId: userId);
      return page.total;
    }

    test('三态数量与判定口径一致（稳定性过阈值但未入已掌握词书算未学习）', () async {
      final counts = await WordBo().getDictWordStatusCounts('dict_main', userId);
      expect(counts.unlearned, 2, reason: 'w1 无记录；w4 记录已毕业但不在已掌握词书');
      expect(counts.learning, 2, reason: 'w2 有记录；w5 已取词未评分');
      expect(counts.mastered, 1, reason: 'w3 在「已掌握」词书内');
      expect(counts.total, 5, reason: '三态之和必须等于词书总词数');
    });

    test('单选各态：只返回该态单词，且总数同步收敛', () async {
      WordStatusFilter only(WordLearningStatus status) =>
          WordStatusFilter.fromCode(status.code);

      expect(await pageSpells(only(WordLearningStatus.unlearned)), ['zebra', 'ant']);
      expect(await totalOf(only(WordLearningStatus.unlearned)), 2);

      expect(await pageSpells(only(WordLearningStatus.learning)), ['bear', 'dog']);
      expect(await totalOf(only(WordLearningStatus.learning)), 2);

      expect(await pageSpells(only(WordLearningStatus.mastered)), ['cat']);
      expect(await totalOf(only(WordLearningStatus.mastered)), 1);
    });

    test('多选组合 = 各态并集；全选 = 不裁剪', () async {
      final unlearnedAndLearning =
          WordStatusFilter.fromCode('UNLEARNED,LEARNING');
      expect(await pageSpells(unlearnedAndLearning), ['zebra', 'bear', 'ant', 'dog']);
      expect(await totalOf(unlearnedAndLearning), 4);

      final masteredAndUnlearned = WordStatusFilter.fromCode('UNLEARNED,MASTERED');
      expect(await pageSpells(masteredAndUnlearned), ['zebra', 'cat', 'ant']);

      expect(await pageSpells(WordStatusFilter.all), ['zebra', 'bear', 'cat', 'ant', 'dog']);
      expect(await totalOf(WordStatusFilter.all), 5);
    });

    test('分页在"可见空间"内切片（offset 按筛选后的序号）', () async {
      final filter = WordStatusFilter.fromCode('UNLEARNED,LEARNING');
      final secondPage = await WordBo().getDictWordsForAPage('dict_main', 2, 2,
          statusFilter: filter, userId: userId);
      expect(secondPage.total, 4);
      expect(secondPage.rows.map((row) => row.word.spell).toList(), ['ant', 'dog']);
    });

    test('字母序分支同样按筛选结果编号排序', () async {
      final filter = WordStatusFilter.fromCode('UNLEARNED');
      expect(await pageSpells(filter, sortAlg: 'ALPHABETICAL'), ['ant', 'zebra']);
    });

    test('getDictWordOrder 返回筛选视图内的序号（0 基），被筛掉返回 -1', () async {
      Future<int> orderOf(String spell, WordStatusFilter filter) async {
        final result = await WordBo().getDictWordOrder('dict_main', spell,
            statusFilter: filter, userId: userId);
        expect(result.success, isTrue);
        // WordBo 返回 1 基序号，-1 表示在当前筛选视图下不存在（provider 层再转成 0 基）
        final order = result.data!;
        return order == -1 ? -1 : order - 1;
      }

      final unlearned = WordStatusFilter.fromCode('UNLEARNED');
      expect(await orderOf('zebra', unlearned), 0);
      expect(await orderOf('ant', unlearned), 1);
      expect(await orderOf('ant', WordStatusFilter.all), 3);
      expect(await orderOf('cat', unlearned), -1, reason: '已掌握的词在"只看未学习"下不可见');

      final alphabetical = await WordBo().getDictWordOrder('dict_main', 'zebra',
          sortAlg: 'ALPHABETICAL', statusFilter: unlearned, userId: userId);
      expect(alphabetical.data! - 1, 1);
    });
  });
}

DictVo _dictVo(String id) => DictVo.c2(id)
  ..name = id
  ..shortName = id
  ..wordCount = 0
  ..isReady = true
  ..isShared = false
  ..visible = true
  ..editable = true;

Future<void> _insertDict(MyDatabase db, DateTime now, String id, String name, String ownerId) {
  return db.into(db.dicts).insert(Dict(
        id: id,
        name: name,
        wordCount: 0,
        isShared: false,
        isReady: true,
        ownerId: ownerId,
        visible: true,
        editable: true,
        deletable: false,
        createTime: now,
        updateTime: now,
      ));
}

Future<void> _insertWord(MyDatabase db, DateTime now, String id, String spell) {
  return db.into(db.words).insert(Word(
        id: id,
        spell: spell,
        popularity: 1,
        createTime: now,
        updateTime: now,
      ));
}

Future<void> _insertDictWord(MyDatabase db, DateTime now, String dictId, String wordId,
    {required int seq}) {
  return db.into(db.dictWords).insert(DictWord(
        dictId: dictId,
        wordId: wordId,
        seq: seq,
        unit: 0,
        createTime: now,
        updateTime: now,
      ));
}

Future<void> _insertLearningWord(
    MyDatabase db, DateTime now, String userId, String wordId, {double? stability}) {
  return db.learningWordsDao.saveEntity(
    LearningWord(
      userId: userId,
      wordId: wordId,
      addDay: 1,
      addTime: now,
      learningOrder: 1,
      isTodayNewWord: false,
      learnedTimes: 1,
      todayLearnedTimes: 0,
      stability: stability,
      state: 1,
      createTime: now,
      updateTime: now,
      isExtra: false,
    ),
    false,
  );
}
