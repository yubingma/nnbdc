import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MyDatabase db;
  const userId = 'user_1';
  const customWordId = 'custom_word_1';
  const systemWordId = 'system_word_1';
  const dictId = 'dict_1';

  final now = DateTime(2026, 10, 21, 20);

  User buildUser() => User(
        id: userId,
        userName: 'tester',
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

  Future<void> insertUserDict() async {
    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '我的生词',
          wordCount: 1,
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

  Future<void> insertWord({
    required String id,
    required String spell,
    required String ownerId,
  }) async {
    await db.into(db.words).insert(Word(
          id: id,
          spell: spell,
          popularity: 1,
          ownerId: ownerId,
          createTime: now,
          updateTime: now,
        ));
  }

  Future<void> insertDictWord(String wordId, {int seq = 7}) async {
    await db.into(db.dictWords).insert(DictWord(
          dictId: dictId,
          wordId: wordId,
          seq: seq,
          unit: 0,
          createTime: now,
          updateTime: now,
        ));
  }

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    final user = buildUser();
    await db.usersDao.saveUser(user, false);
    Global.currentUserId = userId;
    Global.updateUserCache(user);
    await insertUserDict();
  });

  tearDown(() async {
    Global.currentUserId = null;
    await db.close();
  });

  test('新拼写空闲：只改单词本身，词表关联不变', () async {
    await insertWord(id: customWordId, spell: 'aple', ownerId: userId);
    await insertDictWord(customWordId);

    final result = await WordBo().changeCustomWordSpell(customWordId, 'apple');

    expect(result.success, true);
    expect(result.data, customWordId);
    final word = await db.wordsDao.getWordById(customWordId);
    expect(word!.spell, 'apple');
    final link = await db.dictWordsDao.getById(dictId, customWordId);
    expect(link, isNotNull);

    final logs = await db.select(db.userDbLogs).get();
    expect(logs.any((l) => l.tblName == 'words' && l.operate == 'UPDATE'), true);
  });

  test('新拼写撞上本人另一条自建词：拒绝，不产生同拼写记录', () async {
    await insertWord(id: customWordId, spell: 'aple', ownerId: userId);
    await insertWord(id: 'custom_word_2', spell: 'apple', ownerId: userId);

    final result = await WordBo().changeCustomWordSpell(customWordId, 'apple');

    expect(result.success, false);
    expect(result.msg, contains('自建词'));
    final word = await db.wordsDao.getWordById(customWordId);
    expect(word!.spell, 'aple');
  });

  test('新拼写撞上系统词：学习进度、错题次数、学习记录、书签全部迁移过去', () async {
    // 私有词与系统词
    await insertWord(id: customWordId, spell: 'aple', ownerId: userId);
    await insertWord(id: systemWordId, spell: 'apple', ownerId: Global.sysUserId);
    await insertDictWord(customWordId);

    // 私有词的定制释义
    await db.into(db.meaningItems).insert(MeaningItem(
          id: 'meaning_1',
          wordId: customWordId,
          dictId: dictId,
          ciXing: 'n.',
          meaning: '苹果',
          popularity: 1,
          ownerId: userId,
          createTime: now,
          updateTime: now,
        ));

    // 学习记录：私有词最近学过、系统词半年前学过，合并后不能倒退
    await db.into(db.learningWords).insert(LearningWord(
          userId: userId,
          wordId: customWordId,
          addDay: 3,
          addTime: now,
          lastLearningDate: now,
          learningOrder: 5,
          batchId: 9,
          isExtra: false,
          stability: 50,
          difficulty: 5,
          elapsedDays: 1,
          scheduledDays: 3,
          reps: 4,
          lapses: 1,
          state: 2,
          isTodayNewWord: false,
          learnedTimes: 4,
          todayLearnedTimes: 2,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.learningWords).insert(LearningWord(
          userId: userId,
          wordId: systemWordId,
          addDay: 1,
          addTime: now.subtract(const Duration(days: 90)),
          lastLearningDate: now.subtract(const Duration(days: 90)),
          learningOrder: 2,
          batchId: 0,
          isExtra: true,
          stability: 100,
          difficulty: 6,
          elapsedDays: 5,
          scheduledDays: 30,
          reps: 8,
          lapses: 0,
          state: 2,
          isTodayNewWord: false,
          learnedTimes: 6,
          todayLearnedTimes: 1,
          createTime: now.subtract(const Duration(days: 90)),
          updateTime: now.subtract(const Duration(days: 90)),
        ));

    // 错题：两边都有，次数应相加
    await db.into(db.userWrongWords).insert(UserWrongWord(
          userId: userId,
          wordId: customWordId,
          wrongCount: 2,
          inWrongBook: true,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.userWrongWords).insert(UserWrongWord(
          userId: userId,
          wordId: systemWordId,
          wrongCount: 3,
          inWrongBook: false,
          createTime: now,
          updateTime: now,
        ));

    // 学习记录与书签
    await db.into(db.learningLogs).insert(LearningLog(
          id: 'log_1',
          userId: userId,
          wordId: customWordId,
          rating: 3,
          stability: 50,
          difficulty: 5,
          elapsedDays: 1,
          scheduledDays: 3,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.bookMarks).insert(BookMark(
          id: 'bookmark_1',
          userId: userId,
          bookMarkName: 'dict_words_$dictId',
          spell: 'aple',
          position: 1,
          sortAlg: 'ORIGINAL',
          createTime: now,
          updateTime: now,
        ));

    final result = await WordBo().changeCustomWordSpell(customWordId, 'apple');

    expect(result.success, true);
    expect(result.data, systemWordId);

    // 自建词已删除，系统词保留
    expect(await db.wordsDao.getWordById(customWordId), isNull);
    expect(await db.wordsDao.getWordById(systemWordId), isNotNull);

    // 词表条目换成系统词，seq 保留
    expect(await db.dictWordsDao.getById(dictId, customWordId), isNull);
    final movedLink = await db.dictWordsDao.getById(dictId, systemWordId);
    expect(movedLink, isNotNull);
    expect(movedLink!.seq, 7);

    // 定制释义挂到系统词名下，内容不丢
    final meanings = await (db.select(db.meaningItems)..where((mi) => mi.wordId.equals(systemWordId))).get();
    expect(meanings.map((m) => m.meaning), contains('苹果'));

    // 学习进度：取较晚的 FSRS 基线，次数相加，仍算正式词
    final merged = await db.learningWordsDao.getById(userId, systemWordId);
    expect(merged, isNotNull);
    expect(merged!.stability, 50);
    expect(merged.difficulty, 5);
    expect(merged.scheduledDays, 3);
    expect(merged.learnedTimes, 10);
    expect(merged.todayLearnedTimes, 3);
    expect(merged.addDay, 1);
    expect(merged.learningOrder, 2);
    expect(merged.batchId, 9);
    expect(merged.isExtra, false);
    expect(await db.learningWordsDao.getById(userId, customWordId), isNull);

    // 错题次数相加
    final wrong = await db.userWrongWordsDao.getEntity(userId, systemWordId);
    expect(wrong!.wrongCount, 5);
    expect(wrong.inWrongBook, true);
    expect(await db.userWrongWordsDao.getEntity(userId, customWordId), isNull);

    // 学习记录与书签都指向系统词
    final log = await (db.select(db.learningLogs)..where((l) => l.id.equals('log_1'))).getSingle();
    expect(log.wordId, systemWordId);
    final bookmark = await db.bookmarksDao.getById('bookmark_1');
    expect(bookmark!.spell, 'apple');

    // 同步日志：删自建词、词表换词、学习/错题换词都要有
    final logs = await db.select(db.userDbLogs).get();
    expect(logs.any((l) => l.tblName == 'words' && l.operate == 'DELETE'), true);
    expect(logs.any((l) => l.tblName == 'dictWords' && l.operate == 'DELETE'), true);
    expect(logs.any((l) => l.tblName == 'dictWords' && l.operate == 'INSERT' && l.recordId == '$dictId-$systemWordId'),
        true);
    expect(logs.any((l) => l.tblName == 'learningWords' && l.operate == 'DELETE'), true);
    expect(logs.any((l) => l.tblName == 'learningWords' && l.operate == 'UPDATE'), true);
    expect(logs.any((l) => l.tblName == 'userWrongWords' && l.operate == 'DELETE'), true);
    expect(logs.any((l) => l.tblName == 'userWrongWords' && l.operate == 'UPDATE'), true);
    expect(logs.any((l) => l.tblName == 'learningLogs' && l.operate == 'UPDATE'), true);
  });

  test('目标词表已收录系统词：去重后只留一条，词数按实际重算', () async {
    await insertWord(id: customWordId, spell: 'aple', ownerId: userId);
    await insertWord(id: systemWordId, spell: 'apple', ownerId: Global.sysUserId);
    await insertDictWord(customWordId, seq: 7);
    await insertDictWord(systemWordId, seq: 3);

    final result = await WordBo().changeCustomWordSpell(customWordId, 'apple');

    expect(result.success, true);
    expect(await db.dictWordsDao.getById(dictId, customWordId), isNull);
    final kept = await db.dictWordsDao.getById(dictId, systemWordId);
    expect(kept!.seq, 3);
    final dict = await db.dictsDao.findById(dictId);
    expect(dict!.wordCount, 1);
  });

  test('大小写不同的同拼写系统词：同样按替换处理，不会因多条记录报错', () async {
    await insertWord(id: customWordId, spell: 'Apple', ownerId: userId);
    await insertWord(id: systemWordId, spell: 'apple', ownerId: Global.sysUserId);
    await insertDictWord(customWordId);

    final result = await WordBo().changeCustomWordSpell(customWordId, 'apple');

    expect(result.success, true);
    expect(result.data, systemWordId);
    expect(await db.wordsDao.getWordById(customWordId), isNull);
    final link = await db.dictWordsDao.getById(dictId, systemWordId);
    expect(link, isNotNull);
  });

  test('只改大小写、没有撞车：保留在原来的词上', () async {
    await insertWord(id: customWordId, spell: 'aple', ownerId: userId);
    await insertDictWord(customWordId);

    final result = await WordBo().changeCustomWordSpell(customWordId, 'Aple');

    expect(result.success, true);
    expect(result.data, customWordId);
    final word = await db.wordsDao.getWordById(customWordId);
    expect(word!.spell, 'Aple');
  });

  test('系统词不允许修改拼写', () async {
    await insertWord(id: systemWordId, spell: 'apple', ownerId: Global.sysUserId);

    final result = await WordBo().changeCustomWordSpell(systemWordId, 'apples');

    expect(result.success, false);
    expect(result.msg, contains('自己添加'));
  });
}
