import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/sort_alg.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_list/root_family_words.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:toastification/toastification.dart';

/// 同根词词表 Provider 测试：组头行 + 族内词组装、组号连续性、切片、
/// 有效成员不足时整族跳过、只读语义与内存书签。
void main() {
  late MyDatabase db;
  final now = AppClock.now();
  const userId = 'root_family_provider_test_user';

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    WordBo.clearRootFamilyCache();
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

  Future<void> insertCigen(String id, String spell,
      {String category = 'ROOT', String meaning = '含义'}) async {
    await db.into(db.cigens).insert(Cigen(
      id: id,
      description: spell,
      spell: spell,
      category: category,
      meaningCn: meaning,
      meaningEn: null,
      createTime: now,
      updateTime: now,
    ));
  }

  Future<void> insertCigenLink(String cigenId, String wordId) async {
    await db.into(db.cigenWordLinks).insert(CigenWordLink(
      cigenId: cigenId,
      wordId: wordId,
      theExplain: '解析',
      createTime: now,
      updateTime: now,
    ));
  }

  /// spect 族（3 词）+ port 族（2 词），全部在 d1 学习范围内且释义齐备。
  /// 期望行序：spect 组头, expect, inspect, respect, port 组头, export, import
  Future<void> seedTwoFamilies() async {
    await insertDict('d1');
    await insertLearningDict('d1');
    for (final (id, spell) in [
      ('w_expect', 'expect'),
      ('w_inspect', 'inspect'),
      ('w_respect', 'respect'),
      ('w_export', 'export'),
      ('w_import', 'import'),
    ]) {
      await insertWord(id, spell);
      await insertCommonMeaning('mi_$id', id);
      await insertDictWord('d1', id);
    }
    await insertCigen('c_spect', 'spect', meaning: '看');
    for (final id in ['w_expect', 'w_inspect', 'w_respect']) {
      await insertCigenLink('c_spect', id);
    }
    await insertCigen('c_port', 'port', meaning: '搬运');
    for (final id in ['w_export', 'w_import']) {
      await insertCigenLink('c_port', id);
    }
  }

  group('RootFamilyWordsProvider - 组头与族内词组装', () {
    test('数据行只含真实单词（组头不占行），组头经 groupHeaderOf 取得', () async {
      await seedTwoFamilies();

      final provider = RootFamilyWordsProvider();
      final result = await provider.getAPageOfWords(0, 999999);

      // 组头不是数据行：5 个真实单词，无 cigen: 前缀的伪行
      expect(result.total, 5);
      expect(result.rows.map((w) => w.word.id).toList(),
          ['w_expect', 'w_inspect', 'w_respect', 'w_export', 'w_import']);
      expect(result.rows.any((w) => w.word.id!.startsWith('cigen:')), false,
          reason: '组头绝不能作为数据行出现（否则会被随身听当单词播放）');

      // 首词处取到组头，且携带词根/分类/含义/词数
      final header = provider.groupHeaderOf(result.rows.first);
      expect(header, isNotNull);
      expect(header!.word.spell, 'spect');
      expect(header.word.meaningStr, '3 词');
      expect(header.word.shortDesc, '看');
      final cigen = header.tag as CigenVo;
      expect(cigen.category, 'ROOT');
      expect(cigen.meaningCn, '看');

      // 非族首词也能取到所属组头（渲染层只在 isGroupStart 时用，但语义应成立）
      expect(provider.groupHeaderOf(result.rows[1])!.word.spell, 'spect');
      expect(provider.groupHeaderOf(result.rows[3])!.word.spell, 'port');
      expect(provider.groupHeaderOf(null), isNull);

      final member = result.rows.first;
      expect(member.word.meaningItems!.single.meaning, '含义mi_w_expect');
    });

    test('组号按纯单词序列分配（组头不占位）', () async {
      await seedTwoFamilies();
      final provider = RootFamilyWordsProvider();
      final result = await provider.getAPageOfWords(0, 999999);

      // 索引 0..2 = spect 族；3..4 = port 族
      expect(provider.groupIndexOf(0), 1);
      expect(provider.groupIndexOf(1), 1);
      expect(provider.groupIndexOf(2), 1);
      expect(provider.groupIndexOf(3), 2);
      expect(provider.groupIndexOf(4), 2);

      expect(provider.groupOfWord(result.rows[0]), 1);
      expect(provider.groupOfWord(result.rows[4]), 2);
    });

    test('词根组头行不可被当作数据行消费', () async {
      await seedTwoFamilies();
      final provider = RootFamilyWordsProvider();
      final result = await provider.getAPageOfWords(0, 999999);

      expect(provider.groupHeaderOf(result.rows[0]), isNotNull); // 是族首词
      expect(
        result.rows.map((w) => w.word.id).where((id) => id!.startsWith('cigen:')),
        isEmpty,
        reason: '随身听按索引取词时不应取到组头',
      );
    });

    test('切片请求：total 为全量，rows 按区间返回', () async {
      await seedTwoFamilies();
      final provider = RootFamilyWordsProvider();

      final result = await provider.getAPageOfWords(3, 2);

      expect(result.total, 5);
      expect(result.rows.map((w) => w.word.id).toList(),
          ['w_export', 'w_import']);
      // 切片不影响全局组号表
      expect(provider.groupIndexOf(1), 1);
      expect(provider.groupIndexOf(4), 2);
    });

    test('无学习词书 → 空结果', () async {
      final result = await RootFamilyWordsProvider().getAPageOfWords(0, 999999);
      expect(result.total, 0);
      expect(result.rows, isEmpty);
    });

    test('族内有效成员不足 2 个（释义缺失）→ 整族跳过，组头不单独出现', () async {
      await seedTwoFamilies();
      // 移除 spect 族两个成员的释义，只剩 expect 一个有效成员
      await (db.delete(db.meaningItems)
            ..where((m) => m.wordId.isIn(['w_inspect', 'w_respect'])))
          .go();
      WordBo.clearRootFamilyCache();

      final provider = RootFamilyWordsProvider();
      final result = await provider.getAPageOfWords(0, 999999);

      expect(result.rows.map((w) => w.word.id).toList(),
          ['w_export', 'w_import']);
      expect(provider.groupIndexOf(0), 1); // port 组重编号为 1
      expect(provider.groupIndexOf(1), 1);
    });
  });

  group('RootFamilyWordsProvider - 固定排序与只读语义', () {
    test('getSortAlg 固定 original，canCustomizeSort=false，hasUnits=false', () async {
      final provider = RootFamilyWordsProvider();
      expect(await provider.getSortAlg(), WordSortAlg.original);
      expect(provider.canCustomizeSort, false);
      expect(await provider.hasUnits, false);
    });

    test('getWordIndex 按纯单词序列定位（组头不占索引），未收录返回 -1', () async {
      await seedTwoFamilies();
      final provider = RootFamilyWordsProvider();

      expect(await provider.getWordIndex('expect'), 0);
      expect(await provider.getWordIndex('respect'), 2);
      expect(await provider.getWordIndex('export'), 3);
      expect(await provider.getWordIndex('import'), 4);
      expect(await provider.getWordIndex('not_exists'), -1);
    });

    test('只读：deleteWord 返回 false，不改学习数据', () async {
      await seedTwoFamilies();
      final provider = RootFamilyWordsProvider();
      final result = await provider.getAPageOfWords(0, 999999);
      final word = result.rows[1];

      expect(await provider.deleteWord(word), false);
      expect(await db.masteredWordsDao.getMasteredWordIdSet(userId), isEmpty);
    });

    // 掌握/取消掌握会弹 Toast，toast 依赖 ToastificationWrapper
    // （纯单测环境无 Widget 树时会抛断言），故用 widget 测试环境
    testWidgets('掌握/取消掌握返回 false 且 masteredWords 表不变（只读浏览）',
        (tester) async {
      await tester.runAsync(seedTwoFamilies);
      await tester.pumpWidget(ToastificationWrapper(
        child: MaterialApp(home: const Scaffold(body: SizedBox())),
      ));

      late WordWrapper word;
      await tester.runAsync(() async {
        final result =
            await RootFamilyWordsProvider().getAPageOfWords(0, 999999);
        word = result.rows[1];
      });

      final provider = RootFamilyWordsProvider();
      expect(await provider.masterWord(word), false);
      expect(await provider.unmasterWord(word), false);

      await tester.runAsync(() async {
        expect(await db.masteredWordsDao.getMasteredWordIdSet(userId), isEmpty);
      });

      // 结束 toast 的自动关闭计时器，避免 pending timer
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    test('书签为内存态：保存后可读回，不写数据库', () async {
      final provider = RootFamilyWordsBookMarkProvider();
      expect(await provider.getBookMark(), isNull);

      final saved = BookMarkVo(3, 'respect', WordSortAlg.original.code);
      expect(await provider.saveBookMark(saved), true);

      final loaded = await provider.getBookMark();
      expect(loaded!.position, 3);
      expect(loaded.spell, 'respect');
      // 未落库：book_marks 表为空
      expect(await db.select(db.bookMarks).get(), isEmpty);
    });
  });
}
