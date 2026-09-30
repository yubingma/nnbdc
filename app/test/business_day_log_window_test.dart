import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/learning_service.dart';

/// 学习记录（`learning_log`）按业务日窗口归档的边界测试。
///
/// 业务日窗口 = [当地 03:00, 次日 03:00)。凌晨 01:00 从自然日看属于"今天"，
/// 但业务规则里它属于前一业务日；若拿 `AppClock.today()`（业务日的当地 00:00）
/// 当时间戳下界去筛选，就会把它错算进今天。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  const userId = 'business_day_log_user';
  const wordId = 'w_bd_log';

  // 当前时刻 6/16 01:30 → 业务日 6/15，窗口 [6/15 03:00, 6/16 03:00)
  final now = DateTime(2026, 6, 16, 1, 30);
  // 6/15 01:00 属前一业务日 6/14：它落在"业务日当地 00:00 之后"，正是旧口径的错算来源
  final prevBusinessDayTime = DateTime(2026, 6, 15, 1, 0);
  // 6/15 23:50 与 6/16 01:00 同属业务日 6/15（跨自然日，但不跨业务日）
  final assessTime = DateTime(2026, 6, 15, 23, 50);
  final consolidateTime = DateTime(2026, 6, 16, 1, 0);

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
  });

  setUp(() async {
    AppClock.setClock(FakeClock(now));
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    Global.currentUserId = userId;
    Global.updateUserCache(User(
      id: userId,
      userName: 'bd_log_user',
      password: '',
      nickName: 'BdLog',
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
  });

  tearDown(() async {
    ThrottledDbSyncService().reset();
    AppClock.reset();
    await db.close();
    MyDatabase.setInstanceForTesting(null);
  });

  Future<void> addLog(String id, DateTime createTime, FsrsRating rating) async {
    await db.learningLogsDao.saveEntity(
      LearningLog(
        id: id,
        userId: userId,
        wordId: wordId,
        rating: rating.value,
        stability: 1,
        difficulty: 1,
        elapsedDays: 0,
        scheduledDays: 1,
        createTime: createTime,
        updateTime: createTime,
      ),
      false,
    );
  }

  test('getInBusinessDay 只取业务日窗口内的记录：前一日 01:00 不算今天', () async {
    await addLog('log_prev_day', prevBusinessDayTime, FsrsRating.again);
    await addLog('log_assess', assessTime, FsrsRating.easy);
    await addLog('log_consolidate', consolidateTime, FsrsRating.good);

    final rows =
        await db.learningLogsDao.getInBusinessDay(userId, wordIds: [wordId]);

    expect(rows.map((r) => r.id).toList(), ['log_assess', 'log_consolidate'],
        reason: '窗口是 [6/15 03:00, 6/16 03:00)：6/15 01:00 属前一业务日，'
            '其余两条按时间正序；若用 AppClock.today() 当下界，第一条会被错算进来');
  });

  test('今天首条评分口径：前一业务日 01:00 的答错不得算作今天答错', () async {
    await addLog('log_prev_day', prevBusinessDayTime, FsrsRating.again);
    await addLog('log_assess', assessTime, FsrsRating.easy);
    await addLog('log_consolidate', consolidateTime, FsrsRating.good);

    expect(await StudyBo().getTodayWrongWordIds([wordId]), isEmpty,
        reason: '本业务日首条评分是 23:50 的 easy，词不该进"今天答错"集合');
  });

  test('今天首条评分口径：本业务日首条（前一自然日 23:50）是 again 时算今天答错', () async {
    await addLog('log_prev_day', prevBusinessDayTime, FsrsRating.good);
    await addLog('log_assess', assessTime, FsrsRating.again);
    await addLog('log_consolidate', consolidateTime, FsrsRating.good);

    expect(await StudyBo().getTodayWrongWordIds([wordId]), {wordId},
        reason: '23:50 与 01:00 同属业务日 6/15，首条是 23:50 的 again');
  });

  test('「今天首条评分」口径：每词取业务日窗口内最早一条（按 createTime 正序）', () async {
    await addLog('log_prev_day', prevBusinessDayTime, FsrsRating.hard);
    await addLog('log_assess', assessTime, FsrsRating.again);
    await addLog('log_consolidate', consolidateTime, FsrsRating.good);

    // 复习进度环、单词详情页的评分修正、调试面板都靠"结果按 createTime 正序 + 每词首条"推导当天轨道
    final rows =
        await db.learningLogsDao.getInBusinessDay(userId, wordIds: [wordId]);

    expect(rows.map((r) => r.id).toList(), ['log_assess', 'log_consolidate']);
    expect(rows.first.rating, FsrsRating.again.value,
        reason: '今天首条评分是 6/15 23:50 的 again；前一业务日 01:00 的 hard 不得插到最前');
    expect(rows.length, 2, reason: '当天评分日志条数也只数窗口内的这两条');
  });

  test('削减今日计划：前一业务日 01:00 的评分不算"今天学过"，该词仍可被削减', () async {
    // 6/15 01:00 的评分属业务日 6/14；当前 6/16 01:30 属业务日 6/15
    await addLog('log_prev_day', prevBusinessDayTime, FsrsRating.good);

    LearningWord learningWord(String wordId, int learningOrder) => LearningWord(
          userId: userId,
          wordId: wordId,
          addTime: now,
          addDay: 1,
          batchId: 1,
          stability: 0.0,
          isTodayNewWord: true,
          learnedTimes: 0,
          todayLearnedTimes: 0,
          learningOrder: learningOrder,
          isExtra: false,
          createTime: now,
          updateTime: now,
        );

    final todayWords = [
      learningWord('w_bd_log', 1),
      learningWord('w_other', 2),
    ];
    final shrunk = await LearningService.shrinkTodayWords(userId, todayWords, 1);

    expect(shrunk.length, 1,
        reason: '旧口径拿 AppClock.today() 当下界，会把前一业务日 01:00 的评分算成"今天学过"，'
            '这个词被当成已学而受保护，削减整批落空（仍返回 2 个）');
    expect(shrunk.single.wordId, 'w_bd_log', reason: '按批次内顺序削减的是靠后的 w_other');
    expect(shrunk.single.learningOrder, 1);
  });
}
