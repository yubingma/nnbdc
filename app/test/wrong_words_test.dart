import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/date_utils.dart';
import 'package:nnbdc/util/learning_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase database;

  setUp(() {
    database = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('历史错词（错题本）与今日错词功能测试', () {
    test('getAllWrongWords 与 getTodayWrongWords 能够准确区分历史错词与今日错词', () async {
      final now = AppClock.now();
      const userId = 'user_001';

      // 1. 插入一个昨天的错词（历史错词）
      final yesterday = now.subtract(const Duration(days: 2));
      await database.userWrongWordsDao.saveEntity(
        UserWrongWord(
          userId: userId,
          wordId: 'word_yesterday',
          createTime: yesterday,
          updateTime: yesterday,
        ),
        false,
      );

      // 2. 插入一个今天的错词（今日错词 + 历史错词）
      await database.userWrongWordsDao.saveEntity(
        UserWrongWord(
          userId: userId,
          wordId: 'word_today',
          createTime: now,
          updateTime: now,
        ),
        false,
      );

      // 3. 验证今日错词
      final todayWrongWords = await database.userWrongWordsDao.getTodayWrongWords(userId);
      expect(todayWrongWords.length, 1);
      expect(todayWrongWords.first.wordId, 'word_today');

      // 4. 验证历史错词（全量错题本）
      final allWrongWords = await database.userWrongWordsDao.getAllWrongWords(userId);
      expect(allWrongWords.length, 2);
      expect(allWrongWords.first.wordId, 'word_today'); // 最新在前
      expect(allWrongWords.last.wordId, 'word_yesterday');

      // 5. 验证错词总数统计
      final totalCount = await database.userWrongWordsDao.getAllWrongWordsCount(userId);
      expect(totalCount, 2);
    });

    test('removeWrongWord 能够从错题本中单独移出单词', () async {
      const userId = 'user_001';
      final now = AppClock.now();

      await database.userWrongWordsDao.saveEntity(
        UserWrongWord(
          userId: userId,
          wordId: 'word_remove_me',
          createTime: now,
          updateTime: now,
        ),
        false,
      );

      expect(await database.userWrongWordsDao.getAllWrongWordsCount(userId), 1);

      final removed = await database.userWrongWordsDao.removeWrongWord(userId, 'word_remove_me', genLog: false);
      expect(removed, true);
      expect(await database.userWrongWordsDao.getAllWrongWordsCount(userId), 0);
    });

    test('backfillFromLearningLogs 能够从 learning_logs 中自动找回历史做错过的单词', () async {
      const userId = 'user_001';
      final pastDate = DateTime(2025, 1, 15, 10, 0);

      // 在 learning_logs 中插入做错的记录 (rating == 1)
      await database.into(database.learningLogs).insert(
            LearningLog(
              id: 'log_1',
              userId: userId,
              wordId: 'word_historic_1',
              rating: 1, // Again 答错
              stability: 0.5,
              difficulty: 5.0,
              elapsedDays: 0,
              scheduledDays: 1,
              createTime: pastDate,
              updateTime: pastDate,
            ),
          );

      // 在 learning_logs 中插入做对的记录 (rating == 3)
      await database.into(database.learningLogs).insert(
            LearningLog(
              id: 'log_2',
              userId: userId,
              wordId: 'word_correct',
              rating: 3, // Good 答对
              stability: 2.0,
              difficulty: 3.0,
              elapsedDays: 1,
              scheduledDays: 3,
              createTime: pastDate,
              updateTime: pastDate,
            ),
          );

      // 执行回填
      final backfilledCount = await database.userWrongWordsDao.backfillFromLearningLogs(userId);
      expect(backfilledCount, 1);

      // 验证 userWrongWords 中回填成功且只包含做错的词
      final wrongWords = await database.userWrongWordsDao.getAllWrongWords(userId);
      expect(wrongWords.length, 1);
      expect(wrongWords.first.wordId, 'word_historic_1');

      // 重复执行回填，应幂等不重复插入
      final secondBackfilledCount = await database.userWrongWordsDao.backfillFromLearningLogs(userId);
      expect(secondBackfilledCount, 0);
      expect(await database.userWrongWordsDao.getAllWrongWordsCount(userId), 1);
    });

    test('跨天重置逻辑不再清空错词表，确保历史做错词汇沉淀', () async {
      const userId = 'user_001';
      final now = AppClock.now();
      final yesterday = DateUtils.businessDayStart(now.subtract(const Duration(days: 1)));

      final testUser = User(
        id: userId,
        userName: 'test_user',
        password: '',
        nickName: 'Tester',
        email: '',
        gameScore: 0,
        dakaScore: 0,
        learnedDays: 1,
        learningFinished: true,
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
        todayStudyStarted: false,
        totalLearningSeconds: 100,
        todayLearningSeconds: 100,
        lastLearningDate: yesterday,
        createTime: yesterday,
        updateTime: yesterday,
        studyConfig: '{"autoPlayWord":false,"autoPlaySentence":false}',
      );

      await database.into(database.users).insert(testUser);
      await Global.loadUserFromDb();

      await database.userWrongWordsDao.saveEntity(
        UserWrongWord(
          userId: userId,
          wordId: 'word_saved_across_days',
          createTime: yesterday,
          updateTime: yesterday,
        ),
        false,
      );

      // 触发跨天每日数据准备流程
      await LearningService.prepareTodayStudy(false);

      // 验证跨天后错词仍然存在！
      final wrongWords = await database.userWrongWordsDao.getAllWrongWords(userId);
      expect(wrongWords.length, 1);
      expect(wrongWords.first.wordId, 'word_saved_across_days');
    });
  });
}
