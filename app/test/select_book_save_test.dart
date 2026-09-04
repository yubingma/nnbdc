import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';

void main() {
  late MyDatabase database;

  setUp(() {
    database = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('select_book save and word_lists loadData flow', () async {
    const userId = 'test_user_1';

    final now = AppClock.now();

    // Insert user
    await database.into(database.users).insert(UsersCompanion.insert(
      id: userId,
      userName: 'tester',
      nickName: const Value('Tester'),
      gameScore: 0,
      dakaScore: 0,
      dakaDayCount: 0,
      learnedDays: 0,
      wordsPerDay: 20,
      masteredWordsCount: 0,
      cowDung: 0,
      throwDiceChance: 0,
      continuousDakaDayCount: 0,
      maxContinuousDakaDayCount: 0,
    ));

    // Insert 2 dicts
    await database.into(database.dicts).insert(DictsCompanion.insert(
      id: 'dict_cet4',
      name: '四级词汇(2026版)',
      wordCount: 4428,
      isReady: true,
      isShared: false,
      visible: true,
      ownerId: const Value('15118'),
      createTime: now,
    ));

    await database.into(database.dicts).insert(DictsCompanion.insert(
      id: 'dict_kaoyan',
      name: '考研词汇核心版',
      wordCount: 3000,
      isReady: true,
      isShared: false,
      visible: true,
      ownerId: const Value('15118'),
      createTime: now,
    ));

    // Initially, user has dict_cet4
    await database.learningDictsDao.saveEntity(LearningDict(
      userId: userId,
      dictId: 'dict_cet4',
      isPrivileged: false,
      fetchMastered: false,
      sortAlg: 'ORIGINAL',
      createTime: now,
      updateTime: now,
    ), false);

    // Verify initial
    var existingDicts = await database.learningDictsDao.getLearningDictsOfUser(userId);
    expect(existingDicts.length, 1);
    expect(existingDicts.first.dictId, 'dict_cet4');

    // Simulate select_book: user keeps dict_cet4 AND selects dict_kaoyan
    final selectedDictVos = <DictVo>{
      DictVo.c2('dict_cet4'),
      DictVo.c2('dict_kaoyan'),
    };

    // Save logic from select_book.dart
    var learningDictsDao = database.learningDictsDao;
    var currentList = await learningDictsDao.getLearningDictsOfUser(userId);
    for (var existing in currentList) {
      if (!selectedDictVos.contains(DictVo.c2(existing.dictId))) {
        await learningDictsDao.deleteEntity(existing, true);
      }
    }

    for (var dictVo in selectedDictVos) {
      LearningDict? existing = await learningDictsDao.findById(userId, dictVo.id);
      if (existing != null) {
        continue;
      }
      LearningDict learningDict = LearningDict(
        userId: userId,
        dictId: dictVo.id,
        isPrivileged: false,
        fetchMastered: false,
        sortAlg: 'ORIGINAL',
        createTime: now,
        updateTime: now,
      );
      await learningDictsDao.saveEntity(learningDict, false);
    }

    // Now verify learningDictsOfUser
    var updatedLearningDicts = await database.learningDictsDao.getLearningDictsOfUser(userId);
    expect(updatedLearningDicts.length, 2);

    // Simulate word_lists.dart loadData
    final loadedDeskDicts = <Dict>[];
    for (final ld in updatedLearningDicts) {
      final d = await database.dictsDao.findById(ld.dictId);
      if (d != null) {
        loadedDeskDicts.add(d);
      }
    }
    expect(loadedDeskDicts.length, 2);
    expect(loadedDeskDicts[0].id, 'dict_cet4');
    expect(loadedDeskDicts[1].id, 'dict_kaoyan');
  });
}
