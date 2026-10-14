import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';

/// 学习词表批量取释义项时，必须按热度（popularity）升序返回。
///
/// 语义与 `WordBo.getWordMeaningItems` 一致：热度值越小越常用。
/// 查询不能依赖 SQLite 的行物理顺序——那由词书导入的历史顺序决定，与常用度无关。
void main() {
  late MyDatabase db;
  final now = AppClock.now();
  const userId = 'meaning_order_test_user';

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    Global.clearUserCache();
  });

  tearDown(() async {
    await db.close();
    Global.clearUserCache();
  });

  Future<void> insertUser() async {
    await db.usersDao.saveUser(
      User(
        id: userId,
        userName: 'mock_user',
        password: '',
        nickName: 'Tester',
        email: '',
        gameScore: 0,
        dakaScore: 0,
        learnedDays: 0,
        learningFinished: false,
        inviteAwardTaken: false,
        isSuperAdmin: false,
        isAdmin: false,
        isInputor: true,
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
    Global.currentUserId = userId;
  }

  Future<void> insertWord(String id, String spell) async {
    await db.into(db.words).insert(Word(
          id: id,
          spell: spell,
          popularity: 1,
          createTime: now,
          updateTime: now,
        ));
  }

  /// 故意按热度逆序插入，让"返回顺序由排序保证"成为可证伪的断言
  Future<void> insertMeaningItemsOutOfOrder(String wordId) async {
    Future<void> insert(String id, int popularity, String meaning) async {
      await db.into(db.meaningItems).insert(MeaningItem(
            id: id,
            wordId: wordId,
            dictId: Global.commonDictId,
            ciXing: 'n.',
            meaning: meaning,
            popularity: popularity,
            ownerId: '15118',
            createTime: now,
            updateTime: now,
          ));
    }

    await insert('m_third', 3, '第三义');
    await insert('m_first', 1, '第一义');
    await insert('m_second', 2, '第二义');
  }

  Future<void> insertLearningWord(String wordId,
      {bool isTodayNewWord = false, int batchId = 0}) async {
    await db.learningWordsDao.saveEntity(
      LearningWord(
        userId: userId,
        wordId: wordId,
        addDay: 1,
        addTime: now,
        learningOrder: 1,
        isTodayNewWord: isTodayNewWord,
        batchId: batchId,
        learnedTimes: 1,
        todayLearnedTimes: 0,
        state: 1,
        createTime: now,
        updateTime: now,
        isExtra: false,
      ),
      false,
    );
  }

  test('学习中词表：批量释义按热度升序，不随插入顺序', () async {
    await insertUser();
    await insertWord('w_run', 'run');
    await insertMeaningItemsOutOfOrder('w_run');
    await insertLearningWord('w_run');

    final page = await WordBo().getLearningWordsForAPage(0, 10, userId);
    final meanings = page.rows.single.word.meaningItems!
        .map((e) => e.meaning)
        .toList();

    expect(meanings, ['第一义', '第二义', '第三义']);
  });

  test('今日新词词表：批量释义按热度升序', () async {
    await insertUser();
    await insertWord('w_bank', 'bank');
    await insertMeaningItemsOutOfOrder('w_bank');
    await insertLearningWord('w_bank', isTodayNewWord: true, batchId: 1);

    final page = await WordBo().getTodayNewWordsForAPage(0, 10, userId);
    final meanings = page.rows.single.word.meaningItems!
        .map((e) => e.meaning)
        .toList();

    expect(meanings, ['第一义', '第二义', '第三义']);
  });
}
