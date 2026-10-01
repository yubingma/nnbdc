import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/study_consistency_checker.dart';

/// 「学习进度与学习记录不一致」的显式修复测试（内存数据库，不是真机端到端测试）。
///
/// 覆盖三条安全边界：
/// 1. 只在"进度多于记录"时下调，改完必须等于今天的记录条数；
/// 2. 用户确认时看到的进度若已变化，放弃修复（宁可不修，也不能按过期前提改数据）；
/// 3. 只动 `learning_word.today_learned_times`，不动任何学习记录。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  const userId = 'consistency_user';
  const wordId = '15407';

  // 固定在当前业务日内（当地 10:00），避开 03:00 的业务日边界
  final now = DateTime(2026, 10, 1, 10, 0);

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => [],
    );
  });

  setUp(() async {
    AppClock.setClock(FakeClock(now));
    ThrottledDbSyncService().reset();
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);

    final user = User(
      id: userId,
      userName: 'consistency_user',
      password: '',
      nickName: '纪白',
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
      maxContinuousDakaDayCount: 0,
      continuousDakaDayCount: 0,
      todayStudyStarted: true,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      lastLearningDate: AppClock.today(),
      createTime: now,
      updateTime: now,
    );
    Global.currentUserId = userId;
    Global.updateUserCache(user);

    await db.into(db.words).insert(Word(
          id: wordId,
          spell: 'electronic',
          popularity: 100,
          createTime: now,
          updateTime: now,
        ));
  });

  tearDown(() async {
    ThrottledDbSyncService().reset();
    AppClock.reset();
    await db.close();
    MyDatabase.setInstanceForTesting(null);
  });

  /// 造一条"今天走到 [todayLearnedTimes] 个环节"的学习进度
  Future<void> givenLearningWord(int todayLearnedTimes) async {
    await db.into(db.learningWords).insert(LearningWord(
          userId: userId,
          wordId: wordId,
          addTime: now,
          addDay: 1,
          batchId: 1,
          lastLearningDate: now,
          stability: 2.4,
          difficulty: 3.05,
          isTodayNewWord: true,
          learnedTimes: 4,
          todayLearnedTimes: todayLearnedTimes,
          learningOrder: 1,
          createTime: now,
          updateTime: now,
          isExtra: false,
        ));
  }

  /// 造 [count] 条属于当前业务日的评分记录
  Future<void> givenLogs(int count) async {
    for (int i = 0; i < count; i++) {
      await db.learningLogsDao.saveEntity(
        LearningLog(
          id: 'log_$i',
          userId: userId,
          wordId: wordId,
          rating: FsrsRating.easy.value,
          stability: 1,
          difficulty: 1,
          elapsedDays: 0,
          scheduledDays: 1,
          createTime: now.subtract(Duration(minutes: count - i)),
          updateTime: now.subtract(Duration(minutes: count - i)),
        ),
        false,
      );
    }
  }

  StudyConsistencyViolation violationOf({required int progress, required int logs}) {
    return StudyConsistencyViolation(
      rule: StudyConsistencyRule.progressExceedsLogs,
      wordId: wordId,
      spell: 'electronic',
      progress: progress,
      actualLogCount: logs,
    );
  }

  Future<int> currentProgress() async {
    final row = await db.learningWordsDao.getById(userId, wordId);
    return row!.todayLearnedTimes;
  }

  test('进度多于记录时下调到记录条数，且不动任何学习记录', () async {
    await givenLearningWord(4);
    await givenLogs(3);

    final repair = await repairStudyConsistency(
      userId: userId,
      violation: violationOf(progress: 4, logs: 3),
      expectedProgress: 4,
      now: now,
    );

    expect(repair, isNotNull);
    expect(repair!.changed, isTrue);
    expect(repair.progressBefore, 4);
    expect(repair.progressAfter, 3, reason: '改完必须等于今天的记录条数');
    expect(await currentProgress(), 3);

    final logs = await db.learningLogsDao.getInBusinessDay(userId, wordIds: [wordId]);
    expect(logs.length, 3, reason: '修复不得删除或修改任何学习记录');
  });

  test('进度已等于记录条数时不改数据', () async {
    await givenLearningWord(3);
    await givenLogs(3);

    final repair = await repairStudyConsistency(
      userId: userId,
      violation: violationOf(progress: 3, logs: 3),
      expectedProgress: 3,
      now: now,
    );

    expect(repair, isNotNull);
    expect(repair!.changed, isFalse);
    expect(await currentProgress(), 3);
  });

  test('进度少于记录条数时只降不升，不做任何调整', () async {
    // 多设备场景：本机只看到 2 条记录，但进度是 1；往上补齐会把用户没在本机做过的环节放行
    await givenLearningWord(1);
    await givenLogs(2);

    final repair = await repairStudyConsistency(
      userId: userId,
      violation: violationOf(progress: 1, logs: 2),
      expectedProgress: 1,
      now: now,
    );

    expect(repair, isNotNull);
    expect(repair!.changed, isFalse);
    expect(await currentProgress(), 1, reason: '只降不升：不得把进度往上补齐');
  });

  test('今天没有任何记录时不改数据（没有可靠依据）', () async {
    await givenLearningWord(2);

    final repair = await repairStudyConsistency(
      userId: userId,
      violation: violationOf(progress: 2, logs: 0),
      expectedProgress: 2,
      now: now,
    );

    expect(repair, isNotNull);
    expect(repair!.changed, isFalse);
    expect(await currentProgress(), 2);
  });

  test('确认时看到的进度已变化则放弃修复（按过期前提改数据会改错）', () async {
    // 用户确认的是 4，但期间已经变成 3
    await givenLearningWord(3);
    await givenLogs(3);

    final repair = await repairStudyConsistency(
      userId: userId,
      violation: violationOf(progress: 4, logs: 3),
      expectedProgress: 4,
      now: now,
    );

    expect(repair, isNull, reason: '前提已变化必须放弃');
    expect(await currentProgress(), 3);
  });

  test('修复会生成 learning_word 的同步日志，让修复同步到云端与其他设备', () async {
    await givenLearningWord(4);
    await givenLogs(3);

    await repairStudyConsistency(
      userId: userId,
      violation: violationOf(progress: 4, logs: 3),
      expectedProgress: 4,
      now: now,
    );

    final logs = await db.userDbLogsDao.getUserDbLogs(userId);
    final learningWordLogs =
        logs.where((l) => l.tblName == 'learningWords').toList();
    expect(learningWordLogs, isNotEmpty,
        reason: '显式修复必须能被同步出去，否则云端与其他设备看到的还是错值');
    expect(
      logs.where((l) => l.tblName == 'learningLogs'),
      isEmpty,
      reason: '修复只调整今日进度，不应产生任何学习记录的同步日志',
    );
  });

  test('单词已不在学习库时不修（查不到进度行）', () async {
    final repair = await repairStudyConsistency(
      userId: userId,
      violation: violationOf(progress: 4, logs: 3),
      expectedProgress: 4,
      now: now,
    );

    expect(repair, isNull);
  });
}
