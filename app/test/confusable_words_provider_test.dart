import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/sort_alg.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_list/confusable_words.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:toastification/toastification.dart';

void main() {
  late MyDatabase db;
  final now = AppClock.now();
  const userId = 'confusable_provider_test_user';

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    WordBo.clearConfusableCache();
    Global.clearUserCache();
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
    Global.currentUserId = userId;
    Global.updateUserCache(user);
    await db.into(db.users).insert(user);
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

  Future<void> insertCommonMeaning(String id, String wordId) async {
    await db.into(db.meaningItems).insert(MeaningItem(
      id: id,
      wordId: wordId,
      dictId: Global.commonDictId,
      ciXing: 'n.',
      meaning: '含义$id',
      popularity: 1,
      createTime: now,
      ownerId: '15118',
      updateTime: now,
    ));
  }

  /// 插入一条 learning_words 学习记录（锚点：确实学过的词，state>0 表示已评分）
  Future<void> insertLearningWord(String wordId) async {
    await db.learningWordsDao.saveEntity(LearningWord(
      userId: userId,
      wordId: wordId,
      addDay: 1,
      addTime: now,
      learningOrder: 1,
      isTodayNewWord: false,
      learnedTimes: 1,
      todayLearnedTimes: 0,
      state: 1, // 已评分（Learning），离开 New → 算学过
      createTime: now,
      updateTime: now,
    ), false);
  }

  /// 用户"已掌握"词书（findUserMasteredDict 按 ownerId + name='已掌握' 定位）
  Future<void> insertMasteredDict() async {
    await db.into(db.dicts).insert(Dict(
      id: 'mastered_dict',
      name: '已掌握',
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

  /// 构造 5 词（cat/cart/cot/cut/there）的学习词书数据，并返回 confusableClusterSort 期望顺序。
  /// 锚点全部学习过；cat/cot/cut 互为相近词（3 字母互邻）保留，cart(4)/there(5) 为孤立锚点剔除。
  Future<List<String>> seedConfusableData() async {
    await insertDict('d1');
    await insertDict('d2');
    await insertLearningDict('d1');
    await insertLearningDict('d2');
    for (final (id, spell) in [
      ('w_cat', 'cat'),
      ('w_cart', 'cart'),
      ('w_cot', 'cot'),
      ('w_cut', 'cut'),
      ('w_there', 'there'),
    ]) {
      await insertWord(id, spell);
      await insertCommonMeaning('mi_$id', id);
      await insertDictWord('d1', id);
      await insertLearningWord(id); // 锚点：5 词全部学习过
    }
    await insertDictWord('d2', 'w_cat'); // 跨词书重叠，只算一次
    // 期望：锚点字典序 cat < cot < cut（cart/there 孤立锚点被准入剔除）
    return ['w_cat', 'w_cot', 'w_cut'];
  }

  group('ConfusableWordsProvider - 全量加载与切片', () {
    test('getAPageOfWords(0, 999999) 按簇式排序返回全量单词并附带释义', () async {
      final expected = await seedConfusableData();

      final result = await ConfusableWordsProvider().getAPageOfWords(0, 999999);

      expect(result.total, 3);
      expect(result.rows.map((w) => w.word.id).toList(), expected);
      // 每个单词都带上了批量释义（每个词 1 条通用释义）
      for (final w in result.rows) {
        expect(w.word.meaningItems, isNotNull);
        expect(w.word.meaningItems!.length, 1);
        expect(w.word.meaningItems!.first.meaning, '含义mi_${w.word.id}');
      }
    });

    test('getAPageOfWords(fromIndex, pageSize) 切片正确且 total 为全量', () async {
      final expected = await seedConfusableData();

      final result = await ConfusableWordsProvider().getAPageOfWords(1, 2);

      expect(result.total, 3);
      expect(result.rows.map((w) => w.word.id).toList(),
          expected.sublist(1, 3));
    });

    test('无学习词书时返回空结果', () async {
      final result = await ConfusableWordsProvider().getAPageOfWords(0, 999999);
      expect(result.total, 0);
      expect(result.rows, isEmpty);
    });

    test('含释义缺失词的词集：跳过缺失词，其余正常返回（不清空整页）', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      // w_missing 无任何释义（数据异常），其余两词有通用释义
      await insertWord('w_ok1', 'cat');
      await insertWord('w_ok2', 'cot'); // 与 cat 同长 3、距离 1 → 锚点互邻
      await insertWord('w_missing', 'cut'); // 与锚点距离 1 → 相近词（释义缺失）
      await insertCommonMeaning('mi_ok1', 'w_ok1');
      await insertCommonMeaning('mi_ok2', 'w_ok2');
      await insertDictWord('d1', 'w_ok1');
      await insertDictWord('d1', 'w_ok2');
      await insertDictWord('d1', 'w_missing');
      // 锚点：w_ok1/w_ok2 学习过（w_missing 非锚点但与锚点距离 1 → 进相近词，释义缺失被跳过）
      await insertLearningWord('w_ok1');
      await insertLearningWord('w_ok2');

      final result = await ConfusableWordsProvider().getAPageOfWords(0, 999999);

      // 释义缺失词被跳过，其余按簇式序（锚点 cat → cot）返回，总数 = 实际返回数
      expect(result.total, 2);
      expect(result.rows.map((w) => w.word.id).toList(), ['w_ok1', 'w_ok2']);
      expect(result.rows.any((w) => w.word.id == 'w_missing'), false);
    });

    test('当某组因成员缺失释义导致只剩 1 个单词时，自动剔除该孤立单单词组', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      // 组 1：dog / fog（两词均有通用释义，形成合法组）
      await insertWord('w_dog', 'dog');
      await insertWord('w_fog', 'fog');
      await insertCommonMeaning('mi_dog', 'w_dog');
      await insertCommonMeaning('mi_fog', 'w_fog');
      await insertDictWord('d1', 'w_dog');
      await insertDictWord('d1', 'w_fog');
      await insertLearningWord('w_dog');
      await insertLearningWord('w_fog');

      // 组 2：pen / pan，但 pan 缺失释义，导致 pen 成为孤立单单词
      await insertWord('w_pen', 'pen');
      await insertWord('w_pan', 'pan');
      await insertCommonMeaning('mi_pen', 'w_pen');
      // w_pan 无释义
      await insertDictWord('d1', 'w_pen');
      await insertDictWord('d1', 'w_pan');
      await insertLearningWord('w_pen');
      await insertLearningWord('w_pan');

      final result = await ConfusableWordsProvider().getAPageOfWords(0, 999999);

      // pen 孤立组被自动剔除，只保留合法的 dog/fog 组（2 词），组号重编号为 1
      expect(result.total, 2);
      expect(result.rows.map((w) => w.word.id).toList(), ['w_dog', 'w_fog']);
      final provider = ConfusableWordsProvider();
      await provider.getAPageOfWords(0, 999999);
      expect(provider.groupIndexOf(0), 1);
      expect(provider.groupIndexOf(1), 1);
    });
  });

  group('ConfusableWordsProvider - 固定排序与只读语义', () {
    test('getSortAlg 固定 original，canCustomizeSort=false，hasUnits=false', () async {
      final provider = ConfusableWordsProvider();
      expect(await provider.getSortAlg(), WordSortAlg.original);
      expect(provider.canCustomizeSort, false);
      expect(await provider.hasUnits, false);
    });

    test('getWordIndex 按排序后位置定位，未收录单词返回 -1', () async {
      final expected = await seedConfusableData();
      final provider = ConfusableWordsProvider();

      for (var i = 0; i < expected.length; i++) {
        final spell = expected[i].replaceFirst('w_', '');
        expect(await provider.getWordIndex(spell), i);
      }
      expect(await provider.getWordIndex('not_exists'), -1);
    });

    test('deleteWord 返回 false（只读浏览）', () async {
      await seedConfusableData();
      final result = await ConfusableWordsProvider().getAPageOfWords(0, 999999);
      expect(await ConfusableWordsProvider().deleteWord(result.rows.first),
          false);
    });

    test('groupIndexOf 按锚点簇分组：每组连续同组号', () async {
      // 场景 1：cat/cot/cut 互为形近词，聚成 1 个簇（簇头 cat，组员 cot/cut），同组连续同组号 1
      await seedConfusableData();
      var provider = ConfusableWordsProvider();
      await provider.getAPageOfWords(0, 999999);
      expect(provider.groupIndexOf(0), 1);
      expect(provider.groupIndexOf(1), 1);
      expect(provider.groupIndexOf(2), 1);
      expect(provider.groupIndexOf(99), 0); // 越界 → 默认底色

      // 场景 2：加入另一对独立形近词 dog / fog，聚成第 2 个簇
      await insertWord('w_dog', 'dog');
      await insertCommonMeaning('mi_dog', 'w_dog');
      await insertDictWord('d1', 'w_dog');
      await insertWord('w_fog', 'fog');
      await insertCommonMeaning('mi_fog', 'w_fog');
      await insertDictWord('d1', 'w_fog');

      provider = ConfusableWordsProvider();
      final result = await provider.getAPageOfWords(0, 999999);
      expect(result.rows.map((w) => w.word.id).toList(),
          ['w_cat', 'w_cot', 'w_cut', 'w_dog', 'w_fog']);
      // 簇 1（cat 组）：组号全为 1
      expect(provider.groupIndexOf(0), 1);
      expect(provider.groupIndexOf(1), 1);
      expect(provider.groupIndexOf(2), 1);
      // 簇 2（dog 组）：组号全为 2
      expect(provider.groupIndexOf(3), 2);
      expect(provider.groupIndexOf(4), 2);
    });

    testWidgets('unmasterWord 返回 false 且 masteredWords 表不变（只读浏览）',
        (tester) async {
      // 数据准备（真实异步 DB 操作需 runAsync）：w_cat 先处于"已掌握"状态
      await tester.runAsync(() async {
        await insertMasteredDict();
        await db.masteredWordsDao.saveMasteredWord(userId, 'w_cat', false, false);
        expect(await db.masteredWordsDao.isWordMastered(userId, 'w_cat'), true);
      });

      // 掌握/取消掌握会弹 Toast，toast 依赖 ToastificationWrapper
      // （纯单测环境无 Widget 树时会抛断言），故用 widget 测试环境
      await tester.pumpWidget(ToastificationWrapper(
        child: MaterialApp(home: const Scaffold(body: SizedBox())),
      ));

      final provider = ConfusableWordsProvider();
      final wrapper = WordWrapper(WordVo.c2('cat')..id = 'w_cat', null);

      final value = await provider.unmasterWord(wrapper);
      expect(value, false);

      await tester.runAsync(() async {
        // masteredWords 表不变：单词仍处于"已掌握"状态
        expect(await db.masteredWordsDao.isWordMastered(userId, 'w_cat'), true);
      });

      // 结束 toast 的自动关闭计时器，避免 pending timer
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  group('ConfusableWordsBookMarkProvider - 书签持久化', () {
    test('saveBookMark 保存书签成功，getBookMark 能正确读取，支持退出恢复', () async {
      final provider = ConfusableWordsBookMarkProvider();
      // 初始无书签
      expect(await provider.getBookMark(), isNull);

      // 保存书签到第 48 位单词 oak
      final ok = await provider.saveBookMark(BookMarkVo(48, 'oak', 'ORIGINAL'));
      expect(ok, true);

      // 读取书签并验证
      final bookmark = await provider.getBookMark();
      expect(bookmark, isNotNull);
      expect(bookmark!.position, 48);
      expect(bookmark.spell, 'oak');

      // 确认写入了 bookMarks 表且 bookMarkName 正确
      final rows = await (db.select(db.bookMarks)).get();
      expect(rows.length, 1);
      expect(rows.first.bookMarkName, ConfusableWordsBookMarkProvider.bookMarkName);
      expect(rows.first.position, 48);
      expect(rows.first.spell, 'oak');
      expect(rows.first.id.length, 32); // 规范标准的 32 位 UUID
    });
  });
}
