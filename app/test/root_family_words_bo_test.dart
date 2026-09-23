import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';

/// 同根词词表（cigen 词根词缀分族）数据层测试：
/// 范围过滤、成族（≥2 词）、孤立组剔除、一词多根唯一归属、排序、缓存与入口计数。
void main() {
  late MyDatabase db;
  final now = AppClock.now();
  const userId = 'root_family_test_user';

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    WordBo.clearRootFamilyCache();
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

  group('getRootFamilyGroups - 按词根分族', () {
    test('范围内同一词根关联 ≥2 词 → 成族，组内按拼写排序', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w_expect', 'expect');
      await insertWord('w_inspect', 'inspect');
      await insertWord('w_respect', 'respect');
      for (final id in ['w_expect', 'w_inspect', 'w_respect']) {
        await insertDictWord('d1', id);
      }
      await insertCigen('c_spect', 'spect', meaning: '看');
      for (final id in ['w_expect', 'w_inspect', 'w_respect']) {
        await insertCigenLink('c_spect', id);
      }

      final groups = await WordBo().getRootFamilyGroups(userId);
      expect(groups.length, 1);
      final g = groups.single;
      expect(g.cigenId, 'c_spect');
      expect(g.spell, 'spect');
      expect(g.category, 'ROOT');
      expect(g.meaning, '看');
      expect(g.wordIds, ['w_expect', 'w_inspect', 'w_respect']); // 按拼写排序
      expect(g.groupId, 'cigen:c_spect');
    });

    test('范围内只有 1 个关联词的词根 → 孤立组剔除', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w_form', 'form');
      await insertWord('w_other', 'other');
      await insertDictWord('d1', 'w_form');
      await insertDictWord('d1', 'w_other');
      await insertCigen('c_form', 'form');
      await insertCigenLink('c_form', 'w_form'); // 范围内仅 1 词
      await insertCigen('c_other', 'other');
      await insertCigenLink('c_other', 'w_other'); // 范围内仅 1 词

      final groups = await WordBo().getRootFamilyGroups(userId);
      expect(groups, isEmpty);
    });

    test('词根关联的词不在学习范围内 → 不参与分族', () async {
      await insertDict('d1');
      await insertDict('d2');
      await insertLearningDict('d1');
      await insertWord('w_a', 'aaa');
      await insertWord('w_b', 'bbb');
      await insertDictWord('d1', 'w_a');
      await insertDictWord('d1', 'w_b');
      await insertDictWord('d2', 'w_b'); // d2 中也有 bbb，但 d2 未加入学习
      await insertCigen('c_x', 'xxx');
      await insertCigenLink('c_x', 'w_a');
      await insertCigenLink('c_x', 'w_b');

      // d1（含 a、b 两词）在学习范围 → 正常成族
      expect((await WordBo().getRootFamilyGroups(userId)).single.wordIds,
          ['w_a', 'w_b']);

      // 换成只学 d2：范围内关联词只剩 w_b → 不足 2 词不成族（范围外的 w_a 不参与）
      WordBo.clearRootFamilyCache();
      await (db.delete(db.learningDicts)
            ..where((t) => t.userId.equals(userId)))
          .go();
      await insertLearningDict('d2');
      expect(await WordBo().getRootFamilyGroups(userId), isEmpty);
    });

    test('无学习词书 → 空列表 / 计数 0', () async {
      final wordBo = WordBo();
      expect(await wordBo.getRootFamilyGroups(userId), isEmpty);
      expect(await wordBo.getRootFamilyGroupCount(userId), 0);
    });

    test('词根元数据缺失的关联被跳过（不产生幽灵组）', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w_a', 'aaa');
      await insertWord('w_b', 'bbb');
      await insertDictWord('d1', 'w_a');
      await insertDictWord('d1', 'w_b');
      await insertCigenLink('c_missing', 'w_a'); // 无对应 cigen 行
      await insertCigenLink('c_missing', 'w_b');

      expect(await WordBo().getRootFamilyGroups(userId), isEmpty);
    });
  });

  group('getRootFamilyGroups - 一词多根的归属', () {
    test('成员多的词根优先（大族吸收）', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w1', 'aaa1');
      await insertWord('w2', 'aaa2');
      await insertWord('w3', 'aaa3');
      for (final id in ['w1', 'w2', 'w3']) {
        await insertDictWord('d1', id);
      }
      // c_big 关联 3 词，c_small 关联 2 词（与 c_big 共享 w1）
      await insertCigen('c_big', 'big');
      await insertCigen('c_small', 'small');
      for (final id in ['w1', 'w2', 'w3']) {
        await insertCigenLink('c_big', id);
      }
      await insertCigenLink('c_small', 'w1');
      await insertCigenLink('c_small', 'w3');

      final groups = await WordBo().getRootFamilyGroups(userId);
      // c_big 先吸收 w1/w2/w3 → c_small 空 → 剔除
      expect(groups.length, 1);
      expect(groups.single.cigenId, 'c_big');
      expect(groups.single.wordIds, ['w1', 'w2', 'w3']);
    });

    test('成员数相同时 ROOT 优先于 SUFFIX', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w1', 'aaa1');
      await insertWord('w2', 'aaa2');
      await insertDictWord('d1', 'w1');
      await insertDictWord('d1', 'w2');
      await insertCigen('c_suffix', 'suf', category: 'SUFFIX');
      await insertCigen('c_root', 'rot', category: 'ROOT');
      for (final c in ['c_suffix', 'c_root']) {
        await insertCigenLink(c, 'w1');
        await insertCigenLink(c, 'w2');
      }

      final groups = await WordBo().getRootFamilyGroups(userId);
      expect(groups.single.cigenId, 'c_root');
    });

    test('分类与成员数相同 → 按词根拼写字典序，归属确定且可复现', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w1', 'aaa1');
      await insertWord('w2', 'aaa2');
      await insertDictWord('d1', 'w1');
      await insertDictWord('d1', 'w2');
      await insertCigen('c_b', 'bbb');
      await insertCigen('c_a', 'aaa');
      for (final c in ['c_b', 'c_a']) {
        await insertCigenLink(c, 'w1');
        await insertCigenLink(c, 'w2');
      }

      final groups = await WordBo().getRootFamilyGroups(userId);
      expect(groups.single.cigenId, 'c_a');

      // 重复调用结果一致（缓存命中不改变归属）
      expect((await WordBo().getRootFamilyGroups(userId)).single.cigenId, 'c_a');
    });

    test('未知分类排最后（ROOT 优先），仍可成族', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w1', 'aaa1');
      await insertWord('w2', 'aaa2');
      await insertDictWord('d1', 'w1');
      await insertDictWord('d1', 'w2');
      await insertCigen('c_unknown', 'unk', category: 'AFFIX');
      await insertCigen('c_root', 'rot', category: 'ROOT');
      for (final c in ['c_unknown', 'c_root']) {
        await insertCigenLink(c, 'w1');
        await insertCigenLink(c, 'w2');
      }

      final groups = await WordBo().getRootFamilyGroups(userId);
      expect(groups.single.cigenId, 'c_root');
    });
  });

  group('getRootFamilyGroups - 排序与组数', () {
    test('组序按成员数降序；同规模按分类、词根拼写', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      final words = <String, String>{
        'a1': 'worda1', 'a2': 'worda2', 'a3': 'worda3',
        'b1': 'wordb1', 'b2': 'wordb2',
        'c1': 'wordc1', 'c2': 'wordc2',
      };
      for (final e in words.entries) {
        await insertWord(e.key, e.value);
        await insertDictWord('d1', e.key);
      }
      await insertCigen('c_a', 'aaa'); // 3 词
      await insertCigen('c_b', 'bbb'); // 2 词
      await insertCigen('c_c', 'ccc', category: 'SUFFIX'); // 2 词
      for (final id in ['a1', 'a2', 'a3']) {
        await insertCigenLink('c_a', id);
      }
      for (final id in ['b1', 'b2']) {
        await insertCigenLink('c_b', id);
      }
      for (final id in ['c1', 'c2']) {
        await insertCigenLink('c_c', id);
      }

      final groups = await WordBo().getRootFamilyGroups(userId);
      expect([for (final g in groups) g.cigenId], ['c_a', 'c_b', 'c_c']);
    });

    test('计数与成族组数一致', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w1', 'aaa1');
      await insertWord('w2', 'aaa2');
      await insertWord('w3', 'bbb1');
      for (final id in ['w1', 'w2', 'w3']) {
        await insertDictWord('d1', id);
      }
      await insertCigen('c_a', 'aaa');
      await insertCigen('c_b', 'bbb'); // 孤立
      await insertCigenLink('c_a', 'w1');
      await insertCigenLink('c_a', 'w2');
      await insertCigenLink('c_b', 'w3');

      final wordBo = WordBo();
      expect(await wordBo.getRootFamilyGroupCount(userId), 1);
      expect((await wordBo.getRootFamilyGroups(userId)).length, 1);
    });
  });

  group('缓存与入口', () {
    test('学习词书变化触发重算（签名含 dictId 集合）', () async {
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w1', 'aaa1');
      await insertWord('w2', 'aaa2');
      await insertDictWord('d1', 'w1');
      await insertDictWord('d1', 'w2');
      await insertCigen('c_a', 'aaa');
      await insertCigenLink('c_a', 'w1');
      await insertCigenLink('c_a', 'w2');

      final wordBo = WordBo();
      expect((await wordBo.getRootFamilyGroups(userId)).single.wordIds,
          ['w1', 'w2']);

      // 新增一本学习词书（不影响分族结果，但签名变化 → 重新计算）
      await insertDict('d2');
      await insertDictWord('d2', 'w1');
      await insertLearningDict('d2');

      expect(await wordBo.getRootFamilyGroupCount(userId), 1);
    });

    test('缓存按 userId 隔离：换用户学习词书不同 → 各自结果', () async {
      await insertDict('d1');
      await insertDict('d2');
      await insertLearningDict('d1');
      await insertWord('w1', 'aaa1');
      await insertWord('w2', 'aaa2');
      await insertWord('w3', 'bbb1');
      await insertWord('w4', 'bbb2');
      for (final id in ['w1', 'w2']) {
        await insertDictWord('d1', id);
      }
      for (final id in ['w3', 'w4']) {
        await insertDictWord('d2', id);
      }
      await insertCigen('c_a', 'aaa');
      await insertCigen('c_b', 'bbb');
      for (final id in ['w1', 'w2']) {
        await insertCigenLink('c_a', id);
      }
      for (final id in ['w3', 'w4']) {
        await insertCigenLink('c_b', id);
      }

      const otherUser = 'root_family_other_user';
      await db.into(db.users).insert(User(
        id: otherUser,
        userName: 'other',
        password: '',
        nickName: 'Other',
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
      await db.into(db.learningDicts).insert(LearningDict(
        userId: otherUser,
        dictId: 'd2',
        isPrivileged: false,
        fetchMastered: false,
        sortAlg: 'ORIGINAL',
        createTime: now,
        updateTime: now,
      ));

      final wordBo = WordBo();
      expect((await wordBo.getRootFamilyGroups(userId)).single.cigenId, 'c_a');
      expect((await wordBo.getRootFamilyGroups(otherUser)).single.cigenId, 'c_b');
      // 用户 A 的缓存不被用户 B 的调用覆盖
      expect((await wordBo.getRootFamilyGroups(userId)).single.cigenId, 'c_a');
    });

    test('getWordLists 含"同根词"项且计数为成族组数', () async {
      await insertUser();
      await insertDict('d1');
      await insertLearningDict('d1');
      await insertWord('w1', 'aaa1');
      await insertWord('w2', 'aaa2');
      await insertWord('w3', 'bbb1');
      for (final id in ['w1', 'w2', 'w3']) {
        await insertDictWord('d1', id);
      }
      await insertCigen('c_a', 'aaa');
      await insertCigen('c_b', 'bbb');
      await insertCigenLink('c_a', 'w1');
      await insertCigenLink('c_a', 'w2');
      await insertCigenLink('c_b', 'w3'); // 孤立组

      final result = await WordBo().getWordLists();
      expect(result.success, true);
      final entry = result.data!.firstWhere((wl) => wl.name == '同根词');
      expect(entry.wordCount, 1);
    });
  });
}
