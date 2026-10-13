import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/study_consistency_checker.dart';

/// 「学习进度越界」的显式修复测试（内存数据库，不是真机端到端测试）。
///
/// 覆盖四条安全边界：
/// 1. 只在"进度超过轨道长度上限"时截断回上限，绝不把进度往上补；
/// 2. 答错写流水但不推进进度（线上 11 条告警的真实形态）属正常作答，扫描不报、修复不动；
/// 3. 用户确认时看到的进度若已变化，放弃修复（宁可不修，也不能按过期前提改数据）；
/// 4. 只动 `learning_word.today_learned_times`，不动任何学习记录。
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

  /// 造属于当前业务日的评分记录，[ratings] 逐个对应一条流水的评分档
  Future<void> givenLogs(List<int> ratings) async {
    for (int i = 0; i < ratings.length; i++) {
      await db.learningLogsDao.saveEntity(
        LearningLog(
          id: 'log_$i',
          userId: userId,
          wordId: wordId,
          rating: ratings[i],
          stability: 1,
          difficulty: 1,
          elapsedDays: 0,
          scheduledDays: 1,
          createTime: now.subtract(Duration(minutes: ratings.length - i)),
          updateTime: now.subtract(Duration(minutes: ratings.length - i)),
        ),
        false,
      );
    }
  }

  StudyConsistencyViolation violationOf({
    required int progress,
    int trackLenMax = 3,
  }) {
    return StudyConsistencyViolation(
      rule: StudyConsistencyRule.progressExceedsTrack,
      wordId: wordId,
      spell: 'electronic',
      progress: progress,
      trackLenMax: trackLenMax,
    );
  }

  Future<int> currentProgress() async {
    final row = await db.learningWordsDao.getById(userId, wordId);
    return row!.todayLearnedTimes;
  }

  test('进度越界时截断至轨道长度上限，且不动任何学习记录', () async {
    await givenLearningWord(4);
    await givenLogs([FsrsRating.easy.value, FsrsRating.easy.value, FsrsRating.easy.value]);

    final repair = await repairStudyConsistency(
      userId: userId,
      violation: violationOf(progress: 4, trackLenMax: 3),
      expectedProgress: 4,
      trackLenMax: 3,
    );

    expect(repair, isNotNull);
    expect(repair!.changed, isTrue);
    expect(repair.progressBefore, 4);
    expect(repair.progressAfter, 3, reason: '越界截断至轨道上限 3，标为学完');
    expect(await currentProgress(), 3);

    final logs = await db.learningLogsDao.getInBusinessDay(userId, wordIds: [wordId]);
    expect(logs.length, 3, reason: '修复不得删除或修改任何学习记录');
  });

  test('线上现场：测评答对后巩固答错（2 条流水、进度 1）属正常，扫描不报也不动数据', () async {
    await givenLearningWord(1);
    await givenLogs([FsrsRating.easy.value, FsrsRating.again.value]);

    expect(await scanTodayStudyConsistency(userId: userId), isEmpty,
        reason: '答错的环节写流水但不推进进度，这不是"进度与记录对不上"，不得报异常');

    final repair = await repairStudyConsistency(
      userId: userId,
      violation: violationOf(progress: 1),
      expectedProgress: 1,
      trackLenMax: 3,
    );

    expect(repair, isNotNull);
    expect(repair!.changed, isFalse, reason: '进度未越界，一个字都不该改');
    expect(await currentProgress(), 1, reason: '绝不能把进度补到流水条数 —— 那等于替用户跳过还没走的环节');
  });

  test('进度与轨道长度一致且未超轨道时不改数据', () async {
    await givenLearningWord(3);
    await givenLogs([FsrsRating.easy.value, FsrsRating.easy.value, FsrsRating.easy.value]);

    final repair = await repairStudyConsistency(
      userId: userId,
      violation: violationOf(progress: 3, trackLenMax: 3),
      expectedProgress: 3,
      trackLenMax: 3,
    );

    expect(repair, isNotNull);
    expect(repair!.changed, isFalse);
    expect(await currentProgress(), 3);
  });

  test('确认时看到的进度已变化则放弃修复（按过期前提改数据会改错）', () async {
    // 用户确认的是 4，但期间已经变成 3
    await givenLearningWord(3);
    await givenLogs([FsrsRating.easy.value, FsrsRating.easy.value, FsrsRating.easy.value]);

    final repair = await repairStudyConsistency(
      userId: userId,
      violation: violationOf(progress: 4),
      expectedProgress: 4,
    );

    expect(repair, isNull, reason: '前提已变化必须放弃');
    expect(await currentProgress(), 3);
  });

  test('修复会生成 learning_word 的同步日志，让修复同步到云端与其他设备', () async {
    await givenLearningWord(4);
    await givenLogs([FsrsRating.easy.value, FsrsRating.easy.value, FsrsRating.easy.value]);

    await repairStudyConsistency(
      userId: userId,
      violation: violationOf(progress: 4),
      expectedProgress: 4,
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
      violation: violationOf(progress: 4),
      expectedProgress: 4,
    );

    expect(repair, isNull);
  });
}
