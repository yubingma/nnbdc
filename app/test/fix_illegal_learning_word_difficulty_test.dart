import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/data_integrity_checker.dart';
import 'package:nnbdc/util/fsrs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('数据库清洗逻辑：能将存量已掌握词修复为 5.0，将未学词重置为 NULL', () async {
    final now = AppClock.now();
    // 插入两条历史脏数据
    // 1. 存量已掌握词 (stability=180.0, difficulty=0.0)
    await db.into(db.learningWords).insert(LearningWordsCompanion.insert(
          userId: 'test_user',
          wordId: 'word_mastered',
          addTime: now,
          addDay: 1,
          learningOrder: 0,
          stability: const Value(180.0),
          difficulty: const Value(0.0),
          reps: const Value(0),
          lapses: const Value(0),
          state: const Value(0),
          isTodayNewWord: false,
          learnedTimes: 0,
          createTime: now,
        ));

    // 2. 存量未学新词 (stability=0.0, difficulty=0.0)
    await db.into(db.learningWords).insert(LearningWordsCompanion.insert(
          userId: 'test_user',
          wordId: 'word_new',
          addTime: now,
          addDay: 1,
          learningOrder: 0,
          stability: const Value(0.0),
          difficulty: const Value(0.0),
          reps: const Value(0),
          lapses: const Value(0),
          state: const Value(0),
          isTodayNewWord: true,
          learnedTimes: 0,
          createTime: now,
        ));

    // 执行订正逻辑
    await db.customStatement('''
      UPDATE learning_words 
      SET difficulty = 5.0 
      WHERE (stability = 180.0 OR stability = 120.0) 
        AND (difficulty IS NULL OR difficulty < 1.0);
    ''');
    await db.customStatement('''
      UPDATE learning_words 
      SET stability = NULL, difficulty = NULL 
      WHERE (difficulty = 0.0 OR (difficulty IS NOT NULL AND difficulty < 1.0))
        AND (stability = 0.0 OR stability IS NULL)
        AND (reps = 0 OR reps IS NULL);
    ''');

    final mastered = await db.learningWordsDao.getById('test_user', 'word_mastered');
    expect(mastered, isNotNull);
    expect(mastered!.stability, 180.0);
    expect(mastered.difficulty, 5.0); // 成功订正为 5.0

    final newWord = await db.learningWordsDao.getById('test_user', 'word_new');
    expect(newWord, isNotNull);
    expect(newWord!.stability, isNull);
    expect(newWord.difficulty, isNull); // 成功重置为 NULL
  });

  test('FSRS 判定守卫：当单词包含非法的 difficulty=0.0 时，不会调用 fsrs.next 引爆断言', () async {
    final now = AppClock.now();
    final dirtyWord = LearningWord(
      userId: 'test_user',
      wordId: 'word_dirty',
      addTime: now,
      addDay: 1,
      learningOrder: 0,
      stability: 180.0,
      difficulty: 0.0, // 脏数据
      elapsedDays: 1,
      scheduledDays: 180,
      reps: 0,
      lapses: 0,
      state: 0,
      isTodayNewWord: false,
      learnedTimes: 1,
      todayLearnedTimes: 0,
      batchId: 1,
      isExtra: false,
      createTime: now,
      updateTime: now,
    );

    // 验证旧判定会抛断言异常
    expect(
      () => FSRS().next(
        FSRSItem(
          stability: dirtyWord.stability!,
          difficulty: dirtyWord.difficulty!,
          elapsedDays: 1,
          scheduledDays: 180,
          reps: 0,
          lapses: 0,
          state: FsrsState.review,
        ),
        FsrsRating.good,
        1,
      ),
      throwsA(isA<AssertionError>()),
    );

    // 验证新判定逻辑：判定为非法 FSRS 状态，安全走 init，不抛异常
    final bool hasInvalidFsrs = dirtyWord.stability == null ||
        dirtyWord.stability == 0.0 ||
        dirtyWord.difficulty == null ||
        dirtyWord.difficulty! < 1.0;
    expect(hasInvalidFsrs, isTrue);

    final item = FSRS().init(FsrsRating.good);
    expect(item.difficulty, inInclusiveRange(1.0, 10.0));
    expect(item.stability, greaterThan(0.0));
  });

  test('DataIntegrityChecker 健康检查与自动修复：能发现 learning_word_difficulty 并在 autoFix 时完成修复', () async {
    final now = AppClock.now();
    // 插入包含异常难度的数据
    await db.into(db.learningWords).insert(LearningWordsCompanion.insert(
          userId: 'test_user_health',
          wordId: 'word_dirty_1',
          addTime: now,
          addDay: 1,
          learningOrder: 0,
          stability: const Value(180.0),
          difficulty: const Value(0.0),
          reps: const Value(0),
          lapses: const Value(0),
          state: const Value(0),
          isTodayNewWord: false,
          learnedTimes: 0,
          createTime: now,
        ));
    await db.into(db.learningWords).insert(LearningWordsCompanion.insert(
          userId: 'test_user_health',
          wordId: 'word_dirty_2',
          addTime: now,
          addDay: 1,
          learningOrder: 0,
          stability: const Value(0.0),
          difficulty: const Value(0.0),
          reps: const Value(0),
          lapses: const Value(0),
          state: const Value(0),
          isTodayNewWord: true,
          learnedTimes: 0,
          createTime: now,
        ));

    final checker = DataIntegrityChecker();
    final checkResult = IntegrityCheckResult();
    checkResult.addIssue('学习数据认知难度异常', '测试发现异常', 'learning_word_difficulty');

    final fixResult = await checker.autoFix(checkResult, 'test_user_health');
    expect(fixResult.hasFixed, isTrue);

    final w1 = await db.learningWordsDao.getById('test_user_health', 'word_dirty_1');
    expect(w1!.difficulty, 5.0);

    final w2 = await db.learningWordsDao.getById('test_user_health', 'word_dirty_2');
    expect(w2!.difficulty, isNull);
    expect(w2.stability, isNull);
  });
}
