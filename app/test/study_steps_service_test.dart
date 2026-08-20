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

  test('新词未配置时返回默认三组且不落库', () async {
    final cfg = await studyStepsService.getThreeGroupConfig('new');
    expect(cfg.check, 'En2Ch');
    expect(cfg.correct, ['Ch2En']);
    expect(cfg.wrong, ['Ch2En']);

    // 默认值仅运行时返回，不写入数据库
    final dbSteps =
        await db.userStudyStepsDao.getStepsOfScope(testUser.id, 'new');
    expect(dbSteps, isEmpty);
  });

  test('复习词未配置时默认: check=新词 check、correct 空、wrong=[反向互补]', () async {
    final cfg = await studyStepsService.getThreeGroupConfig('review');
    expect(cfg.check, 'En2Ch');
    expect(cfg.correct, isEmpty);
    expect(cfg.wrong, ['Ch2En']);
  });

  group('三组 diff 保存', () {
    Future<List<UserDbLog>> getLogs() => (db.select(db.userDbLogs)
          ..where((l) => l.tblName.equals('userStudySteps')))
        .get();

    test('首次保存 2+2：本地 5 条实体、5 条 INSERT 日志', () async {
      await studyStepsService.saveThreeGroupConfig(
        scope: 'review',
        check: 'En2Ch',
        correct: ['Ch2En', 'EnSentence2Ch'],
        wrong: ['Ch2En', 'ChSentence2En'],
      );
      final config = await studyStepsService.getThreeGroupConfig('review');
      expect(config.check, 'En2Ch');
      expect(config.correct, ['Ch2En', 'EnSentence2Ch']);
      expect(config.wrong, ['Ch2En', 'ChSentence2En']);

      final dbSteps =
          await db.userStudyStepsDao.getStepsOfScope(testUser.id, 'review');
      expect(dbSteps.length, 5);

      final logs = await getLogs();
      expect(logs.where((l) => l.operate == 'INSERT').length, 5);
      expect(logs.where((l) => l.operate == 'DELETE'), isEmpty);
    });

    test('再次保存相同配置：不产生新日志（diff 为空）', () async {
      await studyStepsService.saveThreeGroupConfig(
        scope: 'review',
        check: 'En2Ch',
        correct: ['Ch2En', 'EnSentence2Ch'],
        wrong: ['Ch2En', 'ChSentence2En'],
      );
      final before = (await getLogs()).length;

      await studyStepsService.saveThreeGroupConfig(
        scope: 'review',
        check: 'En2Ch',
        correct: ['Ch2En', 'EnSentence2Ch'],
        wrong: ['Ch2En', 'ChSentence2En'],
      );
      final after = (await getLogs()).length;
      expect(after, before, reason: 'diff 为空时不应产生新日志');
    });

    test('改配置（correct 换一个环节）：只 DELETE 被移除项、INSERT 新增项，交集不动', () async {
      await studyStepsService.saveThreeGroupConfig(
        scope: 'review',
        check: 'En2Ch',
        correct: ['Ch2En', 'EnSentence2Ch'],
        wrong: ['Ch2En'],
      );
      final before = await getLogs();

      // correct: [Ch2En, EnSentence2Ch] → [Ch2En, ChSentence2En]（移除 EnSentence2Ch、新增 ChSentence2En）
      await studyStepsService.saveThreeGroupConfig(
        scope: 'review',
        check: 'En2Ch',
        correct: ['Ch2En', 'ChSentence2En'],
        wrong: ['Ch2En'],
      );

      final after = await getLogs();
      final newLogs = after.skip(before.length).toList();
      expect(newLogs.where((l) => l.operate == 'DELETE').length, 1,
          reason: '只删除被移除的 EnSentence2Ch');
      expect(newLogs.where((l) => l.operate == 'INSERT').length, 1,
          reason: '只插入新增的 ChSentence2En');
      expect(newLogs.where((l) => l.operate == 'UPDATE'), isEmpty,
          reason: '交集的 Ch2En/check/wrong 无变化，不应产生 UPDATE');

      final config = await studyStepsService.getThreeGroupConfig('review');
      expect(config.correct, ['Ch2En', 'ChSentence2En']);
      expect(config.check, 'En2Ch');
      expect(config.wrong, ['Ch2En']);
    });
  });
}
