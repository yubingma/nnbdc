import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/study_config.dart';

/// 释义展示偏好（`StudyConfig.meaningDisplayLimit`）的契约：
/// 1. 默认 0 = 通用词典释义全部展示；
/// 2. 正数 = 只给热度（popularity）最靠前的 N 条，学习页与词表页同一口径；
/// 3. 在学词书里的定制释义永远全部展示，不受条数上限约束。
void main() {
  late MyDatabase db;
  final now = AppClock.now();
  const userId = 'meaning_limit_test_user';
  const customDictId = 'custom_book';

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    Global.clearUserCache();
  });

  tearDown(() async {
    await db.close();
    Global.clearUserCache();
  });

  Future<void> insertUser({int? meaningDisplayLimit}) async {
    final user = User(
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
      studyConfig: meaningDisplayLimit == null
          ? null
          : jsonEncode({'meaningDisplayLimit': meaningDisplayLimit}),
      createTime: now,
      updateTime: now,
    );
    await db.usersDao.saveUser(user, false);
    Global.currentUserId = userId;
    Global.updateUserCache(user);
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

  Future<void> insertMeaning(String id, String wordId, String dictId,
      int popularity, String meaning) async {
    await db.into(db.meaningItems).insert(MeaningItem(
          id: id,
          wordId: wordId,
          dictId: dictId,
          ciXing: 'n.',
          meaning: meaning,
          popularity: popularity,
          ownerId: '15118',
          createTime: now,
          updateTime: now,
        ));
  }

  /// 通用词典的 4 条释义，故意按热度逆序插入
  Future<void> insertCommonMeanings(String wordId) async {
    await insertMeaning('${wordId}_c4', wordId, Global.commonDictId, 4, '第四义');
    await insertMeaning('${wordId}_c1', wordId, Global.commonDictId, 1, '第一义');
    await insertMeaning('${wordId}_c3', wordId, Global.commonDictId, 3, '第三义');
    await insertMeaning('${wordId}_c2', wordId, Global.commonDictId, 2, '第二义');
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

  /// 建一本在学词书，并写入 2 条定制释义
  Future<void> insertCustomDictWithMeanings(String wordId) async {
    await db.into(db.dicts).insert(Dict(
          id: customDictId,
          name: '我的词书',
          wordCount: 1,
          isShared: false,
          isReady: true,
          ownerId: userId,
          visible: true,
          editable: true,
          deletable: false,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.learningDicts).insert(LearningDict(
          userId: userId,
          dictId: customDictId,
          isPrivileged: false,
          fetchMastered: false,
          sortAlg: 'ORIGINAL',
          createTime: now,
          updateTime: now,
        ));
    await insertMeaning('k2', wordId, customDictId, 2, '定制义二');
    await insertMeaning('k1', wordId, customDictId, 1, '定制义一');
  }

  List<String> meaningsOf(List<MeaningItem> items) =>
      [for (final item in items) item.meaning];

  test('默认档（未设置）展示通用词典的全部释义', () async {
    await insertUser();
    await insertWord('w_run', 'run');
    await insertCommonMeanings('w_run');

    expect(StudyConfig.fromCurrentUser().meaningDisplayLimit, 0);
    final items = await WordBo().getWordMeaningItems('w_run', userId);
    expect(meaningsOf(items), ['第一义', '第二义', '第三义', '第四义']);
  });

  test('档位为 2 时只给热度最靠前的 2 条', () async {
    await insertUser(meaningDisplayLimit: 2);
    await insertWord('w_run', 'run');
    await insertCommonMeanings('w_run');

    final items = await WordBo().getWordMeaningItems('w_run', userId);
    expect(meaningsOf(items), ['第一义', '第二义']);
  });

  test('档位为 1 时学习页与词表页口径一致，都只给 1 条', () async {
    await insertUser(meaningDisplayLimit: 1);
    await insertWord('w_run', 'run');
    await insertCommonMeanings('w_run');
    await insertLearningWord('w_run');

    final studyItems = await WordBo().getWordMeaningItems('w_run', userId);
    expect(meaningsOf(studyItems), ['第一义']);

    final page = await WordBo().getLearningWordsForAPage(0, 10, userId);
    final listItems = page.rows.single.word.meaningItems!;
    expect([for (final item in listItems) item.meaning], ['第一义']);
  });

  test('在学词书的定制释义全部展示，不受条数上限约束', () async {
    await insertUser(meaningDisplayLimit: 1);
    await insertWord('w_run', 'run');
    await insertCommonMeanings('w_run');
    await insertCustomDictWithMeanings('w_run');

    final items = await WordBo().getWordMeaningItems('w_run', userId);
    expect(meaningsOf(items), ['定制义一', '定制义二']);
  });

  test('批量取数与逐词取数同一口径', () async {
    await insertUser(meaningDisplayLimit: 2);
    await insertWord('w_run', 'run');
    await insertWord('w_bank', 'bank');
    await insertCommonMeanings('w_run');
    await insertCommonMeanings('w_bank');

    final batch = await WordBo().getWordMeaningItemsBatch(['w_run', 'w_bank'], userId);
    expect(meaningsOf(batch['w_run']!), ['第一义', '第二义']);
    expect(meaningsOf(batch['w_bank']!), ['第一义', '第二义']);
  });
}
