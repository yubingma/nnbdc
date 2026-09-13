// ignore_for_file: avoid_print

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/learning_service.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 批次推进顺序回归测试。
///
/// 背景：用户反馈"新词在英译汉点了『不认识』，汉译英环节却没见到它"。
/// 真实原因是本 App 按【整组横向推进】：每组 10 个词先把同一环节全部走完，
/// 才进入下一个环节（study_bo.dart 的 _compareBatchWords / calculateLearningIndexByWordIndexAndMode）。
/// 本测试把该顺序与"答错词照样在后续环节回归"固化为断言，防止调度被改坏。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  late StudyBo studyBo;

  const int wordTotal = 20;
  const int batchSize = 10;
  // 默认新词轨道：测评 En2Ch → 答对/答错组 [Ch2En] → List
  const List<String> newWordTrack = ['En2Ch', 'Ch2En', 'List'];

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => [],
    );
  });

  setUp(() async {
    AppClock.setClock(FakeClock(DateTime(2026, 5, 20, 8, 0, 0)));

    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    studyBo = StudyBo();
    StudyCacheManager().clear();

    final now = AppClock.now();

    testUser = User(
      id: 'test_user_id',
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
      isInputor: false,
      cowDung: 0,
      throwDiceChance: 0,
      wordsPerDay: wordTotal,
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
      studyConfig: '{"autoPlayWord":false,"autoPlaySentence":false}',
    );
    await db.usersDao.saveUser(testUser, false);

    Global.currentUserId = testUser.id;
    Global.updateUserCache(testUser);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Prefs.write('currentUserId', testUser.id);

    // 不写 userStudySteps：走"未配置"默认三组（新词 En2Ch + 答对/答错 [Ch2En]），
    // 与今日学习计划页"学习轨道"展示的默认值一致

    for (final dict in [
      (id: 'mock_dict_mastered', name: '已掌握'),
      (id: 'mock_dict_raw', name: '生词本'),
    ]) {
      await db.into(db.dicts).insert(Dict(
            id: dict.id,
            name: dict.name,
            wordCount: 0,
            isShared: false,
            isReady: true,
            ownerId: testUser.id,
            visible: true,
            editable: false,
            deletable: false,
            createTime: now,
            updateTime: now,
          ));
    }

    const dictId = 'mock_dict';
    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '批次顺序测试词书',
          wordCount: wordTotal,
          isShared: false,
          isReady: true,
          ownerId: 'sys',
          visible: true,
          editable: false,
          deletable: false,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.learningDicts).insert(LearningDict(
          userId: testUser.id,
          dictId: dictId,
          isPrivileged: false,
          fetchMastered: false,
          sortAlg: 'ORIGINAL',
          createTime: now,
          updateTime: now,
        ));

    for (int i = 0; i < wordTotal; i++) {
      final wordId = 'w_${i + 1}';
      await db.into(db.words).insert(Word(
            id: wordId,
            spell: 'word$i',
            popularity: 100,
            createTime: now,
            updateTime: now,
          ));
      await db.into(db.meaningItems).insert(MeaningItem(
            id: 'mim_${i + 1}',
            wordId: wordId,
            dictId: Global.commonDictId,
            ciXing: 'n.',
            meaning: 'word$i的含义',
            popularity: 100,
            ownerId: Global.sysUserId,
            createTime: now,
            updateTime: now,
          ));
      await db.into(db.dictWords).insert(DictWord(
            dictId: dictId,
            wordId: wordId,
            seq: i + 1,
            unit: 0,
            createTime: now,
            updateTime: now,
          ));
    }
  });

  tearDown(() async {
    await db.close();
    AppClock.reset();
  });

  /// 一整天的出题序列：每次取当前词 → 记录(词, 环节) → 评分 → List 环节批量完成。
  /// [wrongOnceWordId] 指定的词在测评环节按"不认识"（again）作答。
  Future<List<({String wordId, String step, int groupNo, int groupPosition, int groupTotal})>>
      playWholeDay({String? wrongOnceWordId}) async {
    final seq = <({String wordId, String step, int groupNo, int groupPosition, int groupTotal})>[];
    int guard = 0;
    while (guard++ < 300) {
      final res = await studyBo.getWord(false, false);
      expect(res.success, true);
      final data = res.data!;
      if (data.finished || data.learningWord == null) break;

      // List 环节：getWord 以 progress [0, 0] 标识，批量推进整组小结
      if (data.progress != null && data.progress![1] == 0) {
        seq.add((
          wordId: '',
          step: 'List',
          groupNo: 0,
          groupPosition: 0,
          groupTotal: 0,
        ));
        final completeRes = await studyBo.completeListStepForCurrentBatch();
        expect(completeRes.success, true);
        continue;
      }

      final wordId = data.learningWord!.word.id!;
      final stepIndex = data.stepIndex;
      final step = newWordTrack[stepIndex];
      final group = await studyBo.getBatchPhaseProgress(
        wordId: wordId,
        step: step,
      );
      seq.add((
        wordId: wordId,
        step: step,
        groupNo: group?.groupNo ?? -1,
        groupPosition: group?.position ?? -1,
        groupTotal: group?.total ?? -1,
      ));

      final rating = wordId == wrongOnceWordId && step == 'En2Ch'
          ? FsrsRating.again
          : FsrsRating.good;
      await studyBo.getWord(false, true, fsrsRating: rating);
    }
    return seq;
  }

  test('20 词双批次：整组英译汉 → 整组汉译英 → 本组小结，答错词照样在汉译英回归', () async {
    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);
    expect(prep.data![0], wordTotal); // 20 个新词
    expect(prep.data![1], 0); // 0 个旧词

    // 第 1 个词的英译汉点"不认识"
    final seq = await playWholeDay(wrongOnceWordId: 'w_1');
    print(seq.map((e) => e.wordId.isEmpty ? '<本组小结>' : '${e.wordId}@${e.step}').join(' -> '));

    // 1. 顺序：每组内先整组 En2Ch，再整组 Ch2En，最后 List；组间先后推进
    final expected = <String>[
      for (final batchStart in [1, 11]) ...[
        ...List.generate(batchSize, (i) => 'w_${batchStart + i}@En2Ch'),
        ...List.generate(batchSize, (i) => 'w_${batchStart + i}@Ch2En'),
        '<本组小结>',
      ],
    ];
    expect(seq.map((e) => e.wordId.isEmpty ? '<本组小结>' : '${e.wordId}@${e.step}').toList(),
        expected);

    // 2. 反馈给用户的"误解点"回归：答"不认识"的词必须出现在本组汉译英环节
    final w1Index = seq.indexWhere((e) => e.wordId == 'w_1' && e.step == 'Ch2En');
    expect(w1Index, greaterThan(0), reason: 'w_1 答错后必须在本组汉译英环节回来');
    expect(seq[w1Index].wordId, 'w_1');
    expect(seq[w1Index].groupNo, 1);
    expect(seq[w1Index].groupPosition, 1);
    expect(seq[w1Index].groupTotal, batchSize);
  });

  test('第 N 组指示：组号按今日列表每 10 词一组递增', () async {
    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    final seq = await playWholeDay();

    // 前 10 词属第 1 组，后 10 词属第 2 组
    for (final entry in seq) {
      if (entry.step == 'List') {
        expect(entry.groupNo, 0, reason: 'List 环节不展示组内进度指示');
        continue;
      }
      final wordNo = int.parse(entry.wordId.substring(2));
      expect(entry.groupNo, (wordNo - 1) ~/ batchSize + 1, reason: '${entry.wordId}@${entry.step}');
    }
  });

  test('本组环节进度指示与出题顺序一致（第 N 组 · 环节 x/10）', () async {
    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    final seq = await playWholeDay(wrongOnceWordId: 'w_1');

    for (final entry in seq) {
      if (entry.step == 'List') continue;
      // 每组的每个环节队列长度恒为本组词数，位置在 1..10 之间且不重复
      expect(entry.groupTotal, batchSize, reason: '${entry.wordId}@${entry.step}');
      expect(entry.groupPosition, inInclusiveRange(1, batchSize));
    }

    // 本组第一个环节：第 3 个词位于队列第 3 位，且整组顺位恰好 1..10
    expect(seq[2].wordId, 'w_3');
    expect(seq[2].groupPosition, 3);
    expect(
      seq.skip(0).take(batchSize).map((e) => e.groupPosition).toList(),
      List.generate(batchSize, (i) => i + 1),
    );
    // 本组汉译英环节的第一个词：答错的 w_1 排在队列第 1 位
    final firstCh2En = seq.firstWhere((e) => e.step == 'Ch2En');
    expect(firstCh2En.wordId, 'w_1');
    expect(firstCh2En.groupPosition, 1);
    // 本组汉译英环节的最后一个词
    final lastCh2En = seq.lastWhere((e) => e.step == 'Ch2En' && e.wordId == 'w_10');
    expect(lastCh2En.groupPosition, batchSize);
  });

  test('分母是本环节队列长度而非组内词数：复习词答对后不再走汉译英', () async {
    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    // w_5 改造成复习词（同「复习词测评答错进入恢复环节」用例的口径）
    final yesterday = AppClock.today().subtract(const Duration(days: 1));
    await (db.update(db.learningWords)
          ..where((lw) => lw.userId.equals(testUser.id) & lw.wordId.equals('w_5')))
        .write(LearningWordsCompanion(
          stability: const Value(2.4),
          difficulty: const Value(3.05),
          elapsedDays: const Value(0),
          scheduledDays: const Value(2),
          reps: const Value(1),
          lapses: const Value(0),
          state: const Value(2),
          lastLearningDate: Value(yesterday),
          todayLearnedTimes: const Value(0),
        ));
    StudyCacheManager().clear();

    final seq = await playWholeDay();

    // 复习词答对：轨道为 [En2Ch, List]，汉译英环节不含它，故本组 10 词只排 9 个
    expect(seq.any((e) => e.wordId == 'w_5' && e.step == 'Ch2En'), false,
        reason: '复习词答对后不再走汉译英');
    for (final entry in seq) {
      if (entry.step == 'List' || entry.groupNo != 1) continue;
      expect(entry.groupTotal, entry.step == 'En2Ch' ? batchSize : batchSize - 1,
          reason: '${entry.wordId}@${entry.step}');
    }
  });
}
