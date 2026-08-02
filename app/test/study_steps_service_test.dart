import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/study_steps_service.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  late StudyStepsService studyStepsService;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    studyStepsService = StudyStepsService();

    final now = AppClock.now();
    testUser = User(
      id: 'test_legacy_user',
      userName: 'legacy_user',
      password: '',
      nickName: 'LegacyTester',
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
      todayStudyStarted: true,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      lastLearningDate: AppClock.today(),
      createTime: now,
      updateTime: now,
    );
    await db.usersDao.saveUser(testUser, false);

    Global.currentUserId = testUser.id;
    Global.updateUserCache(testUser);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Prefs.write('currentUserId', testUser.id);
  });

  test('老用户仅有En2Ch、Ch2En、List时，getUserStudySteps会自动补全EnSentence2Ch与ChSentence2En且不产生db_log', () async {
    final now = AppClock.now();
    // 模拟老用户本地只有 En2Ch, Ch2En, List 3个步骤
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'En2Ch',
          seq: 0,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'Ch2En',
          seq: 1,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'List',
          seq: 2,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));

    // 清空当前 userDbLogs 表
    await db.delete(db.userDbLogs).go();

    // 调用 getUserStudySteps()
    final steps = await studyStepsService.getUserStudySteps();

    // 验证1: 步骤列表中必须包含 EnSentence2Ch 和 ChSentence2En
    final stepNames = steps.map((s) => s.studyStep).toList();
    expect(stepNames, containsAll(['En2Ch', 'Ch2En', 'EnSentence2Ch', 'ChSentence2En', 'List']));

    // 验证2: List步骤排在最末位
    expect(steps.last.studyStep, equals('List'));

    // 验证3: 持久化库中也有这5个步骤，且两个例句新模式默认未选中 (Inactive)
    final dbSteps = await db.userStudyStepsDao.getUserStudySteps(testUser.id);
    expect(dbSteps.length, equals(5));
    final enSentenceStep = dbSteps.firstWhere((s) => s.studyStep == 'EnSentence2Ch');
    final chSentenceStep = dbSteps.firstWhere((s) => s.studyStep == 'ChSentence2En');
    expect(enSentenceStep.state, equals('Inactive'), reason: '新增加的例句英中环节默认不选中');
    expect(chSentenceStep.state, equals('Inactive'), reason: '新增加的例句中英环节默认不选中');

    // 验证4: 自动补全过程严禁产生 db_log 记录，防后端增量同步报错
    final logs = await db.select(db.userDbLogs).get();
    final studyStepLogs = logs.where((l) => l.tblName == 'userStudySteps' || l.tblName == 'user_study_step');
    expect(studyStepLogs.isEmpty, true, reason: '自动补全缺失步骤不得写入 db_log 日志，防止同步时报错');
  });
}
