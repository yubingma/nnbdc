import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/data_integrity_checker.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「正在学习单词的释义完整性」体检项的判定口径：
/// 必须与学习页取释义的 `WordBo.getWordMeaningItems` 一致 ——
/// 学习词书（含父级词书）里没有该词的定制释义、本地又没有通用释义（dict_id = '0'）时，
/// 学习页会抛「通用释义缺失」，体检就必须把这类词报出来，否则引导用户去体检会看到"全部通过"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  final now = AppClock.now();
  const userId = 'missing_meaning_user';
  const learnDictId = 'd_learn';
  const otherDictId = 'd_other';

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    Global.clearUserCache();

    await db.into(db.users).insert(User(
      id: userId,
      userName: 'missing_meaning_user',
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
    ));
    Global.currentUserId = userId;
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();

    await _insertDict(db, learnDictId, userId, now);
    await _insertDict(db, otherDictId, userId, now);
    // 只把 d_learn 设为学习词书，d_other 是"别的词书"
    await db.into(db.learningDicts).insert(LearningDict(
      userId: userId,
      dictId: learnDictId,
      isPrivileged: false,
      fetchMastered: false,
      sortAlg: 'ORIGINAL',
      createTime: now,
      updateTime: now,
    ));
  });

  tearDown(() async {
    await db.close();
    Global.clearUserCache();
  });

  Future<void> addWord(String wordId, String spell) async {
    await db.into(db.words).insert(Word(
      id: wordId,
      spell: spell,
      popularity: 1,
      createTime: now,
      updateTime: now,
    ));
    await db.into(db.learningWords).insert(LearningWordsCompanion.insert(
          userId: userId,
          wordId: wordId,
          addTime: now,
          addDay: 1,
          learningOrder: 0,
          isTodayNewWord: false,
          learnedTimes: 0,
          createTime: now,
        ));
  }

  Future<void> addMeaning(String id, String wordId, String dictId) async {
    await db.into(db.meaningItems).insert(MeaningItem(
      id: id,
      wordId: wordId,
      dictId: dictId,
      ciXing: 'n.',
      meaning: '释义$id',
      popularity: 1,
      createTime: now,
      ownerId: '15118',
      updateTime: now,
    ));
  }

  Future<IntegrityCheckResult> runCheck() =>
      DataIntegrityChecker().performUserCheck(userId);

  test('别的词书有释义但缺通用释义的词，体检必须报出来', () async {
    await addWord('w0', 'common_ok');
    await addWord('w1', 'custom_in_learn');
    await addWord('w2', 'custom_only_elsewhere');
    await addWord('w3', 'no_meaning_anywhere');

    await addMeaning('m0', 'w0', Global.commonDictId); // 有通用释义 → 学习页不报错
    await addMeaning('m1', 'w1', learnDictId); // 学习词书内有定制释义 → 学习页不报错
    await addMeaning('m2', 'w2', otherDictId); // 只有别的词书有 → 学习页报错
    // w3 任何词典都没有释义 → 学习页报错

    final result = await runCheck();
    expect(result.hasIssue('learning_word_missing_meaning'), isTrue);

    final description = result.issues
        .firstWhere((i) => i.category == 'learning_word_missing_meaning')
        .description;
    expect(description, contains('custom_only_elsewhere'));
    expect(description, contains('no_meaning_anywhere'));
    expect(description, isNot(contains('common_ok')));
    expect(description, isNot(contains('custom_in_learn')));
  });

  test('学习词书内有定制释义、只是缺通用释义的词，不算问题（学习页不会报错）', () async {
    await addWord('w1', 'custom_in_learn');
    await addMeaning('m1', 'w1', learnDictId);

    final result = await runCheck();
    expect(result.hasIssue('learning_word_missing_meaning'), isFalse);
  });

  test('学习词都有通用释义时，体检通过', () async {
    await addWord('w0', 'common_ok');
    await addMeaning('m0', 'w0', Global.commonDictId);

    final result = await runCheck();
    expect(result.hasIssue('learning_word_missing_meaning'), isFalse);
  });
}

Future<void> _insertDict(MyDatabase db, String id, String ownerId, DateTime now) async {
  await db.into(db.dicts).insert(Dict(
    id: id,
    name: id,
    wordCount: 0,
    isShared: false,
    isReady: true,
    ownerId: ownerId,
    visible: true,
    editable: true,
    deletable: false,
    createTime: now,
    updateTime: now,
  ));
}
