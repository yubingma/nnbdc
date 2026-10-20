import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/word_status_filter.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';

/// 批量掌握 / 批量重学：写库规则与单条同源，但整批一次写完。
///
/// 这里只验证数据层（DAO 与 WordBo），界面层的多选状态由控制器承载。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MyDatabase db;
  late DateTime now;
  const userId = 'batch_master_test_user';

  setUp(() async {
    now = AppClock.now();
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    await _seedBase(db, userId, now);
  });

  tearDown(() async {
    // 段位与勋章的判定是 Zone.root 上的微任务，先让它们跑完再关库
    await Future<void>.delayed(const Duration(milliseconds: 50));
    MyDatabase.setInstanceForTesting(null);
    await db.close();
  });

  test('批量掌握：一次写入、重复调用不重复计数、未开始时删掉学习记录', () async {
    final count = await db.masteredWordsDao.setLearningWordsAsMastered(userId, ['w1', 'w2', 'w3']);
    expect(count, 3);
    expect(await db.masteredWordsDao.getMasteredWordIdSet(userId), {'w1', 'w2', 'w3'});

    // 还没开始今天的学习：掌握 = 删掉规划中的学习记录
    expect(await db.learningWordsDao.getById(userId, 'w1'), isNull);

    final user = await db.usersDao.getUserById(userId);
    expect(user!.masteredWordsCount, 3);

    // 重复标记：已在「已掌握」里的词跳过，不重复写入、不重复涨数
    final again = await db.masteredWordsDao.setLearningWordsAsMastered(userId, ['w1', 'w2']);
    expect(again, 0);
    expect(await db.masteredWordsDao.getMasteredWordIdSet(userId), {'w1', 'w2', 'w3'});
    expect((await db.usersDao.getUserById(userId))!.masteredWordsCount, 3);
  });

  test('批量掌握：今天已开始学习时，补满今日环节而不是删记录', () async {
    final user = await db.usersDao.getUserById(userId);
    await db.usersDao.saveUser(user!.copyWith(todayStudyStarted: true), false);

    await db.masteredWordsDao.setLearningWordsAsMastered(userId, ['w1']);

    final learning = await db.learningWordsDao.getById(userId, 'w1');
    expect(learning, isNotNull, reason: '今天已经开背，进度不能因为掌握而消失');
    // 答对组 0 个环节 + 测评 1 + 单词列表 1
    expect(learning!.todayLearnedTimes, 2);
    expect(learning.learnedTimes, 1);
  });

  test('批量重学：移出已掌握、加进生词本、删学习记录', () async {
    await db.masteredWordsDao.setLearningWordsAsMastered(userId, ['w1', 'w2']);

    // 重新给 w1 造一条学习记录，模拟掌握后又有进度
    await db.into(db.learningWords).insert(LearningWord(
      userId: userId,
      wordId: 'w1',
      batchId: 0,
      learningOrder: 1,
      learnedTimes: 3,
      addTime: now,
      addDay: 1,
      todayLearnedTimes: 0,
      isTodayNewWord: false,
      isExtra: false,
      createTime: now,
      updateTime: now,
    ));

    final removed = await db.masteredWordsDao.deleteMasteredWords(userId, ['w1']);
    expect(removed, 1);
    expect(await db.masteredWordsDao.getMasteredWordIdSet(userId), {'w2'});
    expect((await db.usersDao.getUserById(userId))!.masteredWordsCount, 1);

    final rawDict = await db.dictsDao.findUserRawDict(userId);
    expect(
      await db.dictWordsDao.getWordIdsInDict(rawDict!.id, ['w1', 'w2']),
      {'w1'},
      reason: '取消掌握 = 从零重学，词要回到生词本',
    );
    expect(await db.learningWordsDao.getById(userId, 'w1'), isNull, reason: '重学必须清掉旧记忆强度');
  });

  test('全选范围：当前筛选下的全部未掌握词，不是已加载的那一页', () async {
    await db.masteredWordsDao.setLearningWordsAsMastered(userId, ['w1']);

    final all = await WordBo().getSelectableWordIds('src_dict', userId, WordStatusFilter.all);
    expect(all.toSet(), {'w2', 'w3'}, reason: '已掌握的词不再被全选');

    final onlyUnlearned = WordStatusFilter.all
        .toggle(WordLearningStatus.learning)
        .toggle(WordLearningStatus.mastered);
    final unlearned =
        await WordBo().getSelectableWordIds('src_dict', userId, onlyUnlearned);
    expect(unlearned.toSet(), {'w3'}, reason: 'w2 有学习记录，属于学习中');
  });
}

Future<void> _seedBase(MyDatabase db, String userId, DateTime now) async {
  final user = User(
    id: userId,
    userName: 'batch_user',
    password: '',
    nickName: 'Batch',
    email: '',
    gameScore: 0,
    dakaScore: 0,
    learnedDays: 0,
    learningFinished: false,
    inviteAwardTaken: false,
    isSuperAdmin: false,
    isAdmin: false,
    isInputor: false,
    cowDung: 0,
    throwDiceChance: 0,
    wordsPerDay: 20,
    dakaDayCount: 0,
    masteredWordsCount: 0,
    continuousDakaDayCount: 0,
    maxContinuousDakaDayCount: 0,
    todayStudyStarted: false,
    totalLearningSeconds: 0,
    todayLearningSeconds: 0,
    createTime: now,
    updateTime: now,
  );
  await db.usersDao.saveUser(user, false);
  Global.currentUserId = userId;
  Global.updateUserCache(user);

  for (final entry in {'mastered_dict': '已掌握', 'raw_dict': '生词本', 'src_dict': '测试词书'}.entries) {
    await db.into(db.dicts).insert(Dict(
      id: entry.key,
      name: entry.value,
      wordCount: 0,
      isShared: false,
      isReady: true,
      ownerId: userId,
      visible: true,
      editable: false,
      deletable: false,
      createTime: now,
      updateTime: now,
    ));
  }

  for (var i = 1; i <= 3; i++) {
    await db.into(db.words).insert(Word(
      id: 'w$i',
      spell: 'word$i',
      popularity: 100,
      createTime: now,
      updateTime: now,
    ));
    await db.into(db.dictWords).insert(DictWord(
      dictId: 'src_dict',
      wordId: 'w$i',
      seq: i,
      unit: 0,
      createTime: now,
      updateTime: now,
    ));
  }

  // w1、w2 有学习记录（学习中），w3 未学习
  for (var i = 1; i <= 2; i++) {
    await db.into(db.learningWords).insert(LearningWord(
      userId: userId,
      wordId: 'w$i',
      batchId: 1,
      learningOrder: i,
      learnedTimes: 0,
      addTime: now,
      addDay: 1,
      todayLearnedTimes: 0,
      isTodayNewWord: true,
      isExtra: false,
      createTime: now,
      updateTime: now,
    ));
  }
}
