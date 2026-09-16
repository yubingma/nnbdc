import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/app_clock.dart';

/// 复习调度分桶的业务日归一回溯测试。
///
/// 桶归属 = (businessDate(lastLearningDate) + scheduledDays) 与今天业务日的天数差，
/// 因此 lastLearningDate 的存储形态（本地午夜 / UTC 午夜）绝不能让同一个词漂到别的桶。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  const userId = 'bucket_user';

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    Global.currentUserId = userId;
    final now = DateTime(2026, 6, 15, 10);
    await db.usersDao.saveUser(
      User(
        id: userId,
        userName: 'bucket_user',
        password: '',
        nickName: 'Bucket',
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
      ),
      false,
    );
  });

  tearDown(() async {
    ThrottledDbSyncService().reset();
    AppClock.reset();
    await db.close();
  });

  /// 业务日回退用日历运算，避免 Duration 减法在夏令时切换日偏移。
  DateTime bizDaysAgo(int days) => DateTime(2026, 6, 15 - days, 0);

  Future<void> addWord(
    String wordId, {
    required int learnedTimes,
    DateTime? lastLearningDate,
    int scheduledDays = 0,
  }) async {
    await db.into(db.learningWords).insert(LearningWord(
          userId: userId,
          wordId: wordId,
          addDay: 1,
          addTime: bizDaysAgo(30),
          lastLearningDate: lastLearningDate,
          learningOrder: 1,
          isExtra: false,
          isTodayNewWord: learnedTimes == 0,
          learnedTimes: learnedTimes,
          todayLearnedTimes: 0,
          scheduledDays: scheduledDays,
          stability: 0.0,
          batchId: 1,
          createTime: bizDaysAgo(30),
          updateTime: bizDaysAgo(30),
        ));
  }

  test('桶归属按业务日归一：自然日不同但业务日相同的进度必须落进同一个桶', () async {
    AppClock.setClock(FakeClock(DateTime(2026, 6, 15, 10)));

    // 到期日 = 今天：lastLearningDate 业务日 = 6/12，scheduledDays = 3
    final base = bizDaysAgo(3);
    await addWord('w_local', learnedTimes: 1, lastLearningDate: base, scheduledDays: 3);
    // 夜猫子：自然日已是 6/13，但 01:30 仍属业务日 6/12 → 与 w_local 同桶
    await addWord('w_night_owl',
        learnedTimes: 1, lastLearningDate: DateTime(2026, 6, 13, 1, 30), scheduledDays: 3);
    // 逾期 4 天 → 桶 -10；逾期 11 天 → 桶 -20
    await addWord('w_late10', learnedTimes: 1, lastLearningDate: bizDaysAgo(4));
    await addWord('w_late20', learnedTimes: 1, lastLearningDate: bizDaysAgo(11));
    // 新词 → 桶 9999
    await addWord('w_new', learnedTimes: 0);

    final bo = WordBo();
    expect((await bo.getLearningWordsByBucketForAPage(0, 0, 10, userId)).total, 2,
        reason: '自然日 6/13 凌晨 01:30 仍属业务日 6/12，必须与 6/12 同属"今天到期"桶');
    expect((await bo.getLearningWordsByBucketForAPage(-10, 0, 10, userId)).total, 1);
    expect((await bo.getLearningWordsByBucketForAPage(-20, 0, 10, userId)).total, 1);
    expect((await bo.getLearningWordsByBucketForAPage(9999, 0, 10, userId)).total, 1);
    expect((await bo.getLearningWordsByBucketForAPage(1, 0, 10, userId)).total, 0);

    AppClock.reset();
  });
}
