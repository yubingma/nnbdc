import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  late StudyBo studyBo;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async {
        return [];
      },
    );
  });

  test('验证存量词 reps/lapses/elapsedDays/scheduledDays 为 null 时评分流转', () async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    studyBo = StudyBo();
    StudyCacheManager().clear();

    final userId = '6db975f9c8bc4e159d9381cac3067486';
    AppClock.setClock(FakeClock(DateTime(2026, 10, 18, 22, 57, 10)));
    addTearDown(() {
      AppClock.reset();
    });
    final now = AppClock.now();
    testUser = User(
      id: userId,
      userName: 'ap_494c6e1b864c4480',
      password: '',
      nickName: '言 阿',
      email: 'bpvn2hhtm8@privaterelay.appleid.com',
      gameScore: 0,
      dakaScore: 0,
      learnedDays: 20,
      learningFinished: false,
      inviteAwardTaken: false,
      isSuperAdmin: false,
      isAdmin: false,
      isInputor: false,
      cowDung: 0,
      throwDiceChance: 0,
      wordsPerDay: 100,
      dakaDayCount: 17,
      masteredWordsCount: 360,
      maxContinuousDakaDayCount: 0,
      continuousDakaDayCount: 0,
      todayStudyStarted: true,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      lastLearningDate: AppClock.today(),
      createTime: now,
      updateTime: now,
    );
    await db.usersDao.saveUser(testUser, false);
    Global.currentUserId = userId;
    Global.updateUserCache(testUser);

    // 构造一个存量词，类似于线上 6544 (band) 或 17626 (float)，
    // 其 reps 和 lapses 为 null，但 stability 和 difficulty 有值
    final staleLw = LearningWord(
      userId: userId,
      wordId: '6544',
      addDay: 5,
      addTime: now,
      learningOrder: 86,
      batchId: 1,
      isExtra: false,
      stability: 5.8,
      difficulty: 2.11,
      elapsedDays: null,
      scheduledDays: null,
      reps: null,
      lapses: null,
      state: 0,
      isTodayNewWord: false,
      learnedTimes: 9,
      todayLearnedTimes: 0,
      createTime: now,
      updateTime: now,
    );

    final nextFsrs = await studyBo.updateCurrWord(
      isWordMastered: false,
      currWord: staleLw,
      user: testUser,
      now: now,
      db: db,
      allStepsCompletedForWord: false,
      isFirstAttempt: true,
      fsrsRating: FsrsRating.good,
    );
    expect(nextFsrs, isNotNull);
  });
}
