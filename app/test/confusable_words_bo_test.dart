import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/confusable_sort.dart';

void main() {
  late MyDatabase db;
  final now = AppClock.now();
  const userId = 'confusable_test_user';

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    WordBo.clearConfusableCache();
    Global.clearUserCache();
  });

  tearDown(() async {
    await db.close();
    Global.clearUserCache();
  });

  Future<void> insertUser() async {
    final user = User(
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
    );
    await db.usersDao.saveUser(user, false);
    Global.currentUserId = userId;
    Global.updateUserCache(user);
  }

  Future<void> insertDict(String id,
      {int? popularityLimit, String? baseDictId, String? name, String? ownerId}) async {
    await db.into(db.dicts).insert(Dict(
      id: id,
      name: name ?? id,
      wordCount: 0,
      isShared: false,
      isReady: true,
      ownerId: ownerId ?? userId,
      visible: true,
      editable: true,
      deletable: false,
      popularityLimit: popularityLimit,
      baseDictId: baseDictId,
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

  Future<void> insertMeaningItem(
      String id, String wordId, String dictId, int popularity) async {
    await db.into(db.meaningItems).insert(MeaningItem(
      id: id,
      wordId: wordId,
      dictId: dictId,
      ciXing: 'n.',
      meaning: '含义$id',
      popularity: popularity,
      createTime: now,
      ownerId: '15118',
      updateTime: now,
    ));
  }

  /// 插入一条 learning_words 学习记录（"学习过"= 进入过学习轨道，stability 可空可毕业）
  Future<void> insertLearningWord(String wordId, {double? stability}) async {
    await db.learningWordsDao.saveEntity(LearningWord(
      userId: userId,
      wordId: wordId,
      addDay: 1,
      addTime: now,
      learningOrder: 1,
      isTodayNewWord: false,
      learnedTimes: 1,
      todayLearnedTimes: 0,
      stability: stability,
      createTime: now,
      updateTime: now,
    ), false);
  }

  group('getConfusableWordIds - 锚点语义（学习过的词 + 范围内相近词）', () {
    Future<void> seedHouseHorse() async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w_house', 'house');
      await insertWord('w_horse', 'horse');
      await insertDictWord('d1', 'w_house');
      await insertDictWord('d1', 'w_horse');
    }

    test('学习过 house（未掌握），范围内相近 horse(dist=1) → 词表含 house+horse', () async {
      await seedHouseHorse();
      await insertLearningWord('w_house'); // 锚点仅来自 learning_words 记录

      final ids = await WordBo().getConfusableWordIds(userId);
      expect(ids.toSet(), {'w_house', 'w_horse'});
    });

    test('house 与 horse 都学习过 → 都含（锚点聚簇）', () async {
      await seedHouseHorse();
      await insertLearningWord('w_house');
      await insertLearningWord('w_horse');

      final ids = await WordBo().getConfusableWordIds(userId);
      expect(ids.toSet(), {'w_house', 'w_horse'});
    });

    test('都在学习范围内但都没学习过 → 不含（空列表 / 计数 0）', () async {
      await seedHouseHorse();
      // 无 learning_words 记录、无已掌握词书 → 无锚点 → 词表为空

      final wordBo = WordBo();
      expect(await wordBo.getConfusableWordIds(userId), isEmpty);
      expect(await wordBo.getConfusableWordCount(userId), 0);
    });

    test('有学习词书但无锚点 → 空列表 / 计数 0', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w_cat', 'cat');
      await insertWord('w_cart', 'cart');
      await insertDictWord('d1', 'w_cat');
      await insertDictWord('d1', 'w_cart');

      final wordBo = WordBo();
      expect(await wordBo.getConfusableWordIds(userId), isEmpty);
      expect(await wordBo.getConfusableWordCount(userId), 0);
    });

    test('锚点来自已掌握词书（无 learning_word 记录）', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertDict('mastered_dict', name: '已掌握');
      await insertWord('w_house', 'house');
      await insertWord('w_horse', 'horse');
      await insertDictWord('d1', 'w_house');
      await insertDictWord('d1', 'w_horse');
      await db.masteredWordsDao.saveMasteredWord(userId, 'w_house', false, false);

      final ids = await WordBo().getConfusableWordIds(userId);
      expect(ids.toSet(), {'w_house', 'w_horse'});
    });

    test('已毕业 learning_word(stability≥180) 仍是锚点（内联查询无 stability 过滤）', () async {
      await seedHouseHorse();
      // 已毕业：stability = 180（既有 getLearningWordIdSet 过滤 stability<180 会排除已毕业，
      // 内联查询必须包含它，否则词表为空）
      await insertLearningWord('w_house', stability: Constants.graduationStability);

      final ids = await WordBo().getConfusableWordIds(userId);
      expect(ids.toSet(), {'w_house', 'w_horse'});
    });

    test('阈值边界：dist=2 相近词加入、dist=3 排除', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w_cat', 'cat');
      await insertWord('w_crate', 'crate'); // dist(cat, crate) = 2
      await insertWord('w_castle', 'castle'); // dist(cat, castle) = 3
      await insertDictWord('d1', 'w_cat');
      await insertDictWord('d1', 'w_crate');
      await insertDictWord('d1', 'w_castle');
      await insertLearningWord('w_cat');

      final wordBo = WordBo();
      final ids = await wordBo.getConfusableWordIds(userId);
      expect(ids.toSet(), {'w_cat', 'w_crate'});
      expect(ids, isNot(contains('w_castle')));
      expect(await wordBo.getConfusableWordCount(userId), 2);
    });
  });

  group('getConfusableWordIds - 聚合去重与排序', () {
    test('跨词书重叠单词只算一次，排序结果与 confusableSort 直接调用一致', () async {
      await insertDict('d1');
      await insertDict('d2');
      await insertLearningDict('d1');
      await insertLearningDict('d2');

      await insertWord('w_cat', 'cat');
      await insertWord('w_cart', 'cart');
      await insertWord('w_cot', 'cot');
      await insertWord('w_cut', 'cut');
      await insertWord('w_there', 'there');

      // d1: cat/cart/cut；d2: cat(与 d1 重叠)/cot/there
      await insertDictWord('d1', 'w_cat');
      await insertDictWord('d1', 'w_cart');
      await insertDictWord('d1', 'w_cut');
      await insertDictWord('d2', 'w_cat');
      await insertDictWord('d2', 'w_cot');
      await insertDictWord('d2', 'w_there');

      // 锚点：5 词全部学习过 → 词表 = 学习范围全量（去重 + 排序语义与旧版一致）
      for (final id in ['w_cat', 'w_cart', 'w_cot', 'w_cut', 'w_there']) {
        await insertLearningWord(id);
      }

      final wordBo = WordBo();
      final ids = await wordBo.getConfusableWordIds(userId);

      // 去重后 5 个单词，集合正确
      expect(ids.length, 5);
      expect(ids.toSet(), {'w_cat', 'w_cart', 'w_cot', 'w_cut', 'w_there'});

      // 与 confusableSort 直接调用严格一致
      final expected = confusableSort(const [
        (id: 'w_cat', spell: 'cat'),
        (id: 'w_cart', spell: 'cart'),
        (id: 'w_cot', spell: 'cot'),
        (id: 'w_cut', spell: 'cut'),
        (id: 'w_there', spell: 'there'),
      ]);
      expect(ids, expected);
    });

    test('无学习词书返回空列表', () async {
      final wordBo = WordBo();
      expect(await wordBo.getConfusableWordIds(userId), isEmpty);
      expect(await wordBo.getConfusableWordCount(userId), 0);
    });
  });

  group('getConfusableWordIds - 缓存与签名失效', () {
    test('二次调用命中缓存；词书新增单词（锚点不变，B 变 C 应变）/学习词书增删触发重算', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w1', 'cat');
      await insertWord('w2', 'cart');
      await insertDictWord('d1', 'w1');
      await insertDictWord('d1', 'w2');
      await insertLearningWord('w1');
      await insertLearningWord('w2');

      final wordBo = WordBo();
      // 贪心：起始为字典序最小的 cart，然后 cat
      final list1 = await wordBo.getConfusableWordIds(userId);
      expect(list1, ['w2', 'w1']);
      expect(WordBo.isConfusableSortReady(userId), true);

      // 二次调用命中缓存（同一实例，无重算）
      final list2 = await wordBo.getConfusableWordIds(userId);
      expect(identical(list1, list2), true);

      // 词书新增单词 w3（非锚点，但与锚点距离 1 → 进 C）：B 变、A 不变 → 签名变化重算
      await insertWord('w3', 'cot');
      await insertDictWord('d1', 'w3');
      final list3 = await wordBo.getConfusableWordIds(userId);
      expect(identical(list1, list3), false);
      expect(list3, ['w2', 'w1', 'w3']);

      // 删除学习词书 → 签名变化 → 重算为空
      await db.learningDictsDao.deleteEntity(
          LearningDict(
            userId: userId,
            dictId: 'd1',
            isPrivileged: false,
            fetchMastered: false,
            sortAlg: 'ORIGINAL',
            createTime: now,
            updateTime: now,
          ),
          false);
      final list4 = await wordBo.getConfusableWordIds(userId);
      expect(list4, isEmpty);
    });

    test('新增 learning_word / 移入已掌握（A 变）→ 签名变化重算', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertDict('mastered_dict', name: '已掌握');
      await insertWord('w_house', 'house');
      await insertWord('w_horse', 'horse');
      await insertWord('w_hose', 'hose');
      await insertDictWord('d1', 'w_house');
      await insertDictWord('d1', 'w_horse');
      await insertDictWord('d1', 'w_hose');
      await insertLearningWord('w_house');

      final wordBo = WordBo();
      // 锚点 house → 词表 house + horse + hose（后两者与 house 距离 ≤ 2）
      final list1 = await wordBo.getConfusableWordIds(userId);
      expect(list1.toSet(), {'w_house', 'w_horse', 'w_hose'});

      // 新增 learning_word（w_horse 学习过）→ A 变 → 重算（集合不变，缓存对象换新）
      await insertLearningWord('w_horse');
      final list2 = await wordBo.getConfusableWordIds(userId);
      expect(list2.toSet(), {'w_house', 'w_horse', 'w_hose'});
      expect(identical(list1, list2), false);

      // 移入已掌握（w_hose 进已掌握词书）→ A 变 → 重算
      await db.masteredWordsDao.saveMasteredWord(userId, 'w_hose', false, false);
      final list3 = await wordBo.getConfusableWordIds(userId);
      expect(list3.toSet(), {'w_house', 'w_horse', 'w_hose'});
      expect(identical(list2, list3), false);
    });
  });

  group('getConfusableWordCount - 计数与排序共用缓存', () {
    test('计数未命中时完整计算一次并缓存；排序与计数共用同一次计算，长度一致', () async {
      await insertDict('d1');
      await insertDict('d2');
      await insertLearningDict('d1');
      await insertLearningDict('d2');
      await insertWord('w1', 'cat');
      await insertWord('w2', 'cart');
      await insertWord('w3', 'cot');
      await insertDictWord('d1', 'w1');
      await insertDictWord('d1', 'w2');
      await insertDictWord('d2', 'w2'); // 重叠
      await insertDictWord('d2', 'w3');
      // 锚点 w1/w2；w3 与锚点距离 1 → 进 C，词表共 3 词
      await insertLearningWord('w1');
      await insertLearningWord('w2');

      final wordBo = WordBo();

      // 先计数：未命中 → 完整计算（过滤 + 排序）一次并缓存（原"计数不触发排序缓存"断言反转）
      expect(await wordBo.getConfusableWordCount(userId), 3);
      expect(WordBo.isConfusableSortReady(userId), true);

      // 再排序：命中同一缓存，与计数共用同一次计算的结果
      final ids = await wordBo.getConfusableWordIds(userId);
      expect(ids.length, 3);
      final idsAgain = await wordBo.getConfusableWordIds(userId);
      expect(identical(ids, idsAgain), true);

      // 计数与列表长度一致（复用缓存长度）
      expect(await wordBo.getConfusableWordCount(userId), ids.length);
    });
  });

  group('getConfusableMeaningsInBatch - 与 getWordMeaningItems 一致', () {
    test('定制释义优先 / 最大 popularityLimit / min-3 保底 / 学习中与已掌握豁免', () async {
      // 词书：d1 用户词书 limit=30，d2 系统词书 limit=50 → 最大 limit=50
      await insertDict('d1', popularityLimit: 30);
      await insertDict('d2', popularityLimit: 50, ownerId: '15118');
      await insertLearningDict('d1');
      await insertLearningDict('d2');
      // 已掌握词书（ownerId=userId 且 name='已掌握'）
      await insertDict('mastered_dict', name: '已掌握');

      for (final s in ['w1', 'w2', 'w3', 'w4', 'w5']) {
        await insertWord(s, s);
        await insertDictWord('d1', s);
      }

      // 通用释义（dictId = Global.commonDictId）
      await insertMeaningItem('mi_w1_c1', 'w1', Global.commonDictId, 10);
      await insertMeaningItem('mi_w1_c2', 'w1', Global.commonDictId, 20);
      // w2 有 5 条通用释义，limit=50 过滤后剩 4 条（≥3，不触发保底），popularity=60 的被过滤
      await insertMeaningItem('mi_w2_c1', 'w2', Global.commonDictId, 10);
      await insertMeaningItem('mi_w2_c2', 'w2', Global.commonDictId, 20);
      await insertMeaningItem('mi_w2_c3', 'w2', Global.commonDictId, 30);
      await insertMeaningItem('mi_w2_c4', 'w2', Global.commonDictId, 40);
      await insertMeaningItem('mi_w2_c5', 'w2', Global.commonDictId, 60);
      await insertMeaningItem('mi_w3_c1', 'w3', Global.commonDictId, 55);
      await insertMeaningItem('mi_w3_c2', 'w3', Global.commonDictId, 65);
      await insertMeaningItem('mi_w3_c3', 'w3', Global.commonDictId, 75);
      // w4/w5 各 4 条通用释义（40 ≤ limit，60/70/80 > limit）：
      // 若豁免不生效 → limit=50 过滤后剩 1 条 → min-3 保底只返回 3 条；
      // 豁免生效 → 返回全部 4 条（含 popularity=80 的 c4），可真正区分豁免分支
      await insertMeaningItem('mi_w4_c1', 'w4', Global.commonDictId, 40);
      await insertMeaningItem('mi_w4_c2', 'w4', Global.commonDictId, 60);
      await insertMeaningItem('mi_w4_c3', 'w4', Global.commonDictId, 70);
      await insertMeaningItem('mi_w4_c4', 'w4', Global.commonDictId, 80);
      await insertMeaningItem('mi_w5_c1', 'w5', Global.commonDictId, 40);
      await insertMeaningItem('mi_w5_c2', 'w5', Global.commonDictId, 60);
      await insertMeaningItem('mi_w5_c3', 'w5', Global.commonDictId, 70);
      await insertMeaningItem('mi_w5_c4', 'w5', Global.commonDictId, 80);

      // w1 定制释义（学习词书 d1，优先返回）
      await insertMeaningItem('mi_w1_d1_1', 'w1', 'd1', 5);
      await insertMeaningItem('mi_w1_d1_2', 'w1', 'd1', 7);

      // w4 学习中（豁免 limit）；w5 已掌握（豁免 limit）
      await db.into(db.learningWords).insert(LearningWord(
        userId: userId,
        wordId: 'w4',
        addDay: 1,
        addTime: now,
        learningOrder: 1,
        isTodayNewWord: false,
        learnedTimes: 1,
        todayLearnedTimes: 0,
        createTime: now,
        updateTime: now,
      ));
      await insertDictWord('mastered_dict', 'w5');

      final wordBo = WordBo();
      final batch =
          await wordBo.getConfusableMeaningsInBatch({'w1', 'w2', 'w3', 'w4', 'w5'}, userId);

      // 逐词对比：批量结果与 getWordMeaningItems 完全一致
      for (final w in ['w1', 'w2', 'w3', 'w4', 'w5']) {
        final perWord = await wordBo.getWordMeaningItems(w, userId);
        expect(batch[w], perWord, reason: '批量释义与逐词结果不一致: $w');
      }

      // 语义抽查
      // 定制释义优先
      expect(batch['w1']!.map((m) => m.id).toList(), ['mi_w1_d1_1', 'mi_w1_d1_2']);
      // 最大 popularityLimit=50，过滤掉 popularity=60 的释义（剩余 4 条 ≥3，不触发保底）
      expect(batch['w2']!.map((m) => m.id).toList(),
          ['mi_w2_c1', 'mi_w2_c2', 'mi_w2_c3', 'mi_w2_c4']);
      // 全部被过滤 → min-3 保底取常用度最靠前 3 条
      expect(batch['w3']!.map((m) => m.id).toList(),
          ['mi_w3_c1', 'mi_w3_c2', 'mi_w3_c3']);
      // 学习中豁免 limit：返回全部 4 条（若未豁免只会剩 min-3 保底的 3 条）
      expect(batch['w4']!.length, 4);
      expect(batch['w4']!.map((m) => m.id).toList(),
          ['mi_w4_c1', 'mi_w4_c2', 'mi_w4_c3', 'mi_w4_c4']);
      // 已掌握豁免 limit
      expect(batch['w5']!.length, 4);
      expect(batch['w5']!.map((m) => m.id).toList(),
          ['mi_w5_c1', 'mi_w5_c2', 'mi_w5_c3', 'mi_w5_c4']);
    });

    test('学习词书 baseDictId 父级词库的定制释义优先', () async {
      // d2 的父级词库 base_dict 提供 w6 的定制释义（不在 learning_dicts 中，靠 baseDictId 展开命中）
      await insertDict('d1', popularityLimit: 50);
      await insertDict('base_dict', popularityLimit: null);
      await insertDict('d2', popularityLimit: 50, baseDictId: 'base_dict');
      await insertLearningDict('d1');
      await insertLearningDict('d2');

      await insertWord('w6', 'w6');
      await insertDictWord('d1', 'w6');

      // 通用释义 + 父级词库定制释义
      await insertMeaningItem('mi_w6_c1', 'w6', Global.commonDictId, 10);
      await insertMeaningItem('mi_w6_c2', 'w6', Global.commonDictId, 20);
      await insertMeaningItem('mi_w6_base_1', 'w6', 'base_dict', 5);
      await insertMeaningItem('mi_w6_base_2', 'w6', 'base_dict', 8);

      final wordBo = WordBo();
      final batch = await wordBo.getConfusableMeaningsInBatch({'w6'}, userId);
      final perWord = await wordBo.getWordMeaningItems('w6', userId);

      // 与逐词结果一致，且父级词库定制释义优先于通用释义
      expect(batch['w6'], perWord);
      expect(batch['w6']!.map((m) => m.id).toList(), ['mi_w6_base_1', 'mi_w6_base_2']);
    });

    test('通用释义缺失时抛异常（与 getWordMeaningItems 一致）', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w_missing', 'w_missing');
      await insertDictWord('d1', 'w_missing');
      // 不插入任何释义

      final wordBo = WordBo();
      expect(wordBo.getConfusableMeaningsInBatch({'w_missing'}, userId),
          throwsA(isA<Exception>()));
      expect(wordBo.getWordMeaningItems('w_missing', userId), throwsA(isA<Exception>()));
    });

    test('空 wordIds 输入返回空 Map', () async {
      final wordBo = WordBo();
      expect(await wordBo.getConfusableMeaningsInBatch(<String>{}, userId), isEmpty);
    });
  });

  group('getWordLists - 易混淆单词入口', () {
    test('列表包含"易混淆单词"项且计数为去重单词数', () async {
      await insertUser();
      await insertDict('d1');
      await insertDict('d2');
      await insertLearningDict('d1');
      await insertLearningDict('d2');
      await insertWord('w1', 'cat');
      await insertWord('w2', 'cart');
      await insertWord('w3', 'cot');
      await insertDictWord('d1', 'w1');
      await insertDictWord('d1', 'w2');
      await insertDictWord('d2', 'w2'); // 重叠
      await insertDictWord('d2', 'w3');
      // 锚点：3 词全部学习过
      await insertLearningWord('w1');
      await insertLearningWord('w2');
      await insertLearningWord('w3');

      final result = await WordBo().getWordLists();
      expect(result.success, true);
      final entry = result.data!.firstWhere((wl) => wl.name == '易混淆单词');
      expect(entry.wordCount, 3);
    });
  });
}
