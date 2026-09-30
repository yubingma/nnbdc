import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/date_utils.dart';
import 'package:nnbdc/util/learning_log_repair.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归测试：客户端一次性修复"同一次作答被重复计分"的存量脏数据。
///
/// 覆盖：词 A（重复日志 + 被污染的记忆字段回填 + 派生计数回滚）、词 B（已掌握不回填记忆
/// 字段但计数仍回滚，含 stability 哨兵值与「已掌握」词书两种口径）、词 C（跨天正常日志
/// 不受影响）、幂等（重复执行结果不变）、限流续跑（单次上限 + 待续跑标记）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  const userId = 'u1';

  // 基准时间取整秒：drift 的 DateTime 列存 Unix 秒，同一簇的两条日志必然落在同一秒
  final base = DateTime(2026, 1, 1, 12, 0, 0);
  const duplicateGap = Duration(milliseconds: 30);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    db = MyDatabase(NativeDatabase.memory());
    // DbLogUtil.logOperation 依赖 MyDatabase.instance 单例，必须指向测试库才能写入同步日志
    MyDatabase.setInstanceForTesting(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> insertLog(
    String wordId,
    DateTime time, {
    required double stability,
    double difficulty = 5.0,
    int elapsedDays = 0,
    int scheduledDays = 1,
  }) async {
    final id = Util.uuid();
    await db.into(db.learningLogs).insert(LearningLog(
          id: id,
          userId: userId,
          wordId: wordId,
          rating: 3,
          stability: stability,
          difficulty: difficulty,
          elapsedDays: elapsedDays,
          scheduledDays: scheduledDays,
          createTime: time,
          updateTime: time,
        ));
    return id;
  }

  Future<void> insertLearningWord(
    String wordId, {
    double? stability,
    double? difficulty,
    int? elapsedDays,
    int? scheduledDays,
    int learnedTimes = 1,
    int todayLearnedTimes = 0,
  }) async {
    await db.into(db.learningWords).insert(LearningWord(
          userId: userId,
          wordId: wordId,
          addDay: 1,
          addTime: base,
          learningOrder: 1,
          isExtra: false,
          isTodayNewWord: true,
          learnedTimes: learnedTimes,
          todayLearnedTimes: todayLearnedTimes,
          stability: stability,
          difficulty: difficulty,
          elapsedDays: elapsedDays,
          scheduledDays: scheduledDays,
          createTime: base,
          updateTime: base,
        ));
  }

  Future<void> insertDailyStat(DateTime time, int reviewCount) async {
    await db.into(db.userStudyDailyStats).insert(UserStudyDailyStat(
          userId: userId,
          date: DateUtils.businessDate(time),
          studySeconds: 0,
          reviewCount: reviewCount,
          createTime: base,
          updateTime: base,
        ));
  }

  Future<UserStudyDailyStat?> dailyStat() {
    return (db.select(db.userStudyDailyStats)
          ..where((t) => t.userId.equals(userId)))
        .getSingleOrNull();
  }

  Future<void> markAsMasteredInDict(String wordId) async {
    await db.into(db.dicts).insert(Dict(
          id: 'dict-mastered',
          isReady: true,
          isShared: false,
          name: '已掌握',
          wordCount: 1,
          ownerId: userId,
          visible: true,
          editable: false,
          deletable: true,
          createTime: base,
          updateTime: base,
        ));
    await db.into(db.dictWords).insert(DictWord(
          dictId: 'dict-mastered',
          wordId: wordId,
          seq: 1,
          unit: 0,
          createTime: base,
          updateTime: base,
        ));
  }

  Future<List<LearningLog>> logsOf(String wordId) {
    return (db.select(db.learningLogs)
          ..where((l) => l.wordId.equals(wordId))
          ..orderBy([
            (l) => OrderingTerm(expression: l.createTime),
            (l) => OrderingTerm(expression: CustomExpression<int>('rowid')),
          ]))
        .get();
  }

  Future<List<UserDbLog>> syncLogsOf(String tblName, String operate) {
    return (db.select(db.userDbLogs)
          ..where((l) => l.tblName.equals(tblName) & l.operate.equals(operate)))
        .get();
  }

  test('词A：重复日志被删除，learning_words 回填为现存最早日志的真值', () async {
    // 被重复计分污染的现状：learning_words 是重复那条的错误值（5.8/2.4/0/0）
    await insertLearningWord('wordA', stability: 5.8, difficulty: 2.4, elapsedDays: 0, scheduledDays: 0);
    await insertLog('wordA', base, stability: 57.0, difficulty: 7.0, elapsedDays: 3, scheduledDays: 15);
    final dupId = await insertLog('wordA', base.add(duplicateGap), stability: 5.8, difficulty: 2.4);

    await LearningLogRepair.repairDuplicateLearningLogs(db);

    final logs = await logsOf('wordA');
    expect(logs.length, 1, reason: '同一簇只保留最早一条');
    expect(logs.single.id, isNot(dupId));
    expect(logs.single.stability, 57.0);

    final word = await db.learningWordsDao.getById(userId, 'wordA');
    expect(word!.stability, 57.0);
    expect(word.difficulty, 7.0);
    expect(word.elapsedDays, 3);
    expect(word.scheduledDays, 15);

    // 每条删除都要有 learningLogs 的 DELETE 同步日志（端云收敛依据）
    final deleteLogs = await syncLogsOf('learningLogs', 'DELETE');
    expect(deleteLogs.map((l) => l.recordId), [dupId]);
    expect(deleteLogs.single.userId, userId);
    final deletedJson = jsonDecode(deleteLogs.single.record) as Map<String, dynamic>;
    expect(deletedJson.keys.toList(), ['id'],
        reason: 'DELETE 日志只带 id（缩体），避免大批量删除把单次同步 POST 撑爆');
    expect(deletedJson['id'], dupId);

    // 回填要写 learningWords 的 UPDATE 同步日志，记录标识是复合主键 user_id-word_id
    final updateLogs = await syncLogsOf('learningWords', 'UPDATE');
    expect(updateLogs.map((l) => l.recordId), ['$userId-wordA']);
  });

  test('词A2：重复日志派生的计数一并回滚（review_count / learnedTimes / todayLearnedTimes）', () async {
    // 现状：一次作答被计了两次 → 该词学了 2 次，当天有 3 条评分日志（第 3 条很正常，不该动）
    await insertLearningWord('wordA2',
        stability: 5.8, difficulty: 2.4, learnedTimes: 2, todayLearnedTimes: 2);
    await insertDailyStat(base, 3);
    await insertLog('wordA2', base, stability: 57.0, difficulty: 7.0, elapsedDays: 3, scheduledDays: 15);
    await insertLog('wordA2', base.add(duplicateGap), stability: 5.8, difficulty: 2.4);
    await insertLog('wordA2', base.add(const Duration(minutes: 5)), stability: 60.0);

    await LearningLogRepair.repairDuplicateLearningLogs(db);

    final word = await db.learningWordsDao.getById(userId, 'wordA2');
    expect(word!.learnedTimes, 1, reason: '删 1 条重复日志，learnedTimes 回滚 1');
    expect(word.todayLearnedTimes, 1, reason: 'todayLearnedTimes 同步回滚 1');
    expect((await dailyStat())!.reviewCount, 2, reason: '当日 review_count 从 3 回滚到 2');
  });

  test('派生计数回滚下限为 0（已是 0 时不减成负数）', () async {
    await insertLearningWord('wordA3',
        stability: 5.8, difficulty: 2.4, learnedTimes: 0, todayLearnedTimes: 0);
    await insertDailyStat(base, 0);
    await insertLog('wordA3', base, stability: 57.0, elapsedDays: 3);
    await insertLog('wordA3', base.add(duplicateGap), stability: 5.8);

    await LearningLogRepair.repairDuplicateLearningLogs(db);

    final word = await db.learningWordsDao.getById(userId, 'wordA3');
    expect(word!.learnedTimes, 0);
    expect(word.todayLearnedTimes, 0);
    expect((await dailyStat())!.reviewCount, 0);
  });

  test('词B：已掌握词（stability 达掌握线）只去重日志+回滚计数，不回填记忆字段', () async {
    await insertLearningWord('wordB',
        stability: Constants.graduationStability, difficulty: 6.0,
        learnedTimes: 3, todayLearnedTimes: 3);
    await insertLog('wordB', base, stability: 130.0);
    await insertLog('wordB', base.add(duplicateGap), stability: 5.0);

    await LearningLogRepair.repairDuplicateLearningLogs(db);

    expect((await logsOf('wordB')).length, 1, reason: '重复日志仍要去重');
    final word = await db.learningWordsDao.getById(userId, 'wordB');
    expect(word!.stability, Constants.graduationStability, reason: '已掌握词的 stability 不得被日志改回去');
    expect(word.learnedTimes, 2, reason: '已掌握词的派生计数仍需回滚');
    final updateLogs = await syncLogsOf('learningWords', 'UPDATE');
    expect(updateLogs.map((l) => l.recordId), ['$userId-wordB'],
        reason: '计数回滚仍需落库并上报，已掌握词只豁免记忆字段');
    final record = jsonDecode(updateLogs.single.record) as Map<String, dynamic>;
    expect(record['stability'], Constants.graduationStability,
        reason: '上报的实体里 stability 仍是毕业哨兵值');
  });

  test('词B2：已在「已掌握」词书里的词，同样只回滚计数不回填', () async {
    await markAsMasteredInDict('wordB2');
    await insertLearningWord('wordB2', stability: 20.0, difficulty: 5.0);
    await insertLog('wordB2', base, stability: 30.0);
    await insertLog('wordB2', base.add(duplicateGap), stability: 20.0);

    await LearningLogRepair.repairDuplicateLearningLogs(db);

    expect((await logsOf('wordB2')).length, 1);
    final word = await db.learningWordsDao.getById(userId, 'wordB2');
    expect(word!.stability, 20.0);
    final updateLogs = await syncLogsOf('learningWords', 'UPDATE');
    expect(updateLogs.map((l) => l.recordId), ['$userId-wordB2']);
    final record = jsonDecode(updateLogs.single.record) as Map<String, dynamic>;
    expect(record['stability'], 20.0, reason: '已掌握词书记忆字段不回填');
  });

  test('词C：跨天正常日志不受影响', () async {
    await insertLearningWord('wordC', stability: 20.0, difficulty: 5.0);
    await insertLog('wordC', base, stability: 10.0);
    await insertLog('wordC', base.add(const Duration(days: 1)), stability: 20.0);

    await LearningLogRepair.repairDuplicateLearningLogs(db);

    expect((await logsOf('wordC')).length, 2);
    final word = await db.learningWordsDao.getById(userId, 'wordC');
    expect(word!.stability, 20.0);
    expect(await syncLogsOf('learningLogs', 'DELETE'), isEmpty);
    expect(await syncLogsOf('learningWords', 'UPDATE'), isEmpty);
  });

  test('幂等：再跑一次修复，日志与记忆字段都不再变化', () async {
    await insertLearningWord('wordA', stability: 5.8, difficulty: 2.4, elapsedDays: 0, scheduledDays: 0);
    await insertLog('wordA', base, stability: 57.0, difficulty: 7.0, elapsedDays: 3, scheduledDays: 15);
    await insertLog('wordA', base.add(duplicateGap), stability: 5.8, difficulty: 2.4);
    await insertLog('wordC', base, stability: 10.0);
    await insertLog('wordC', base.add(const Duration(days: 1)), stability: 20.0);

    await LearningLogRepair.repairDuplicateLearningLogs(db);

    final logsAfterFirstRun = await db.select(db.learningLogs).get();
    final wordAAfterFirstRun = await db.learningWordsDao.getById(userId, 'wordA');
    final syncLogsAfterFirstRun = await db.select(db.userDbLogs).get();

    await LearningLogRepair.repairDuplicateLearningLogs(db);

    final logsAfterSecondRun = await db.select(db.learningLogs).get();
    final wordAAfterSecondRun = await db.learningWordsDao.getById(userId, 'wordA');
    final syncLogsAfterSecondRun = await db.select(db.userDbLogs).get();

    expect(logsAfterSecondRun.length, logsAfterFirstRun.length, reason: '重复执行不应再删任何行');
    expect(wordAAfterSecondRun!.stability, wordAAfterFirstRun!.stability);
    expect(wordAAfterSecondRun.difficulty, wordAAfterFirstRun.difficulty);
    expect(wordAAfterSecondRun.elapsedDays, wordAAfterFirstRun.elapsedDays);
    expect(wordAAfterSecondRun.scheduledDays, wordAAfterFirstRun.scheduledDays);
    expect(wordAAfterSecondRun.learnedTimes, wordAAfterFirstRun.learnedTimes);
    expect(syncLogsAfterSecondRun.length, syncLogsAfterFirstRun.length, reason: '重复执行不应再产生同步日志');
  });

  test('限流续跑：单次最多删 limit 条并置待续跑标记，续跑清完后清标记', () async {
    // 3 个词各 1 条重复 → 共 3 条待删
    for (final w in ['w1', 'w2', 'w3']) {
      await insertLearningWord(w, stability: 5.8);
      await insertLog(w, base, stability: 57.0, elapsedDays: 3);
      await insertLog(w, base.add(duplicateGap), stability: 5.8);
    }

    final first = await LearningLogRepair.repairDuplicateLearningLogs(db, limit: 2);
    expect(first.completed, false, reason: '触达单次上限必须上报未完成');
    expect(first.deletedLogs, 2);
    expect(Prefs.read<bool>(LearningLogRepair.pendingPrefsKey), true,
        reason: '未清完要置待续跑标记，供启动钩子续跑');

    // 模拟 App 启动钩子续跑
    await LearningLogRepair.resumePendingIfNeeded();

    expect(await db.select(db.learningLogs).get(), hasLength(3), reason: '3 个词各留 1 条');
    expect(Prefs.read<bool>(LearningLogRepair.pendingPrefsKey), false, reason: '清完后必须清标记');
  });
}
