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
import 'package:nnbdc/util/study_config.dart';
import 'package:nnbdc/services/user_privilege_manager.dart';
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
  /// [wrongOnceWordId] 指定的词在测评环节按"不认识"（again）作答；
  /// [wrongAtCh2EnWordId] 指定的词在汉译英环节按"不认识"作答（测评仍是答对）。
  Future<
      List<
          ({
            String wordId,
            String step,
            int groupNo,
            int groupPosition,
            int groupTotal,
            String trackName
          })>>
      playWholeDay({String? wrongOnceWordId, String? wrongAtCh2EnWordId}) async {
    final seq = <({
      String wordId,
      String step,
      int groupNo,
      int groupPosition,
      int groupTotal,
      String trackName
    })>[];
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
          trackName: '',
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
        trackName: group?.trackName ?? '',
      ));

      final rating = (wordId == wrongOnceWordId && step == 'En2Ch') ||
              (wordId == wrongAtCh2EnWordId && step == 'Ch2En')
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

    // 3. 进度按"当前词所在轨道"分别计数：第 1 组的汉译英由两条轨道汇聚而来 ——
    //    w_1 答错自成一条（1 个词），其余 9 个答对自成一条，各数各的。
    expect(seq[w1Index].trackName, '新词答错');
    expect(seq[w1Index].groupPosition, 1);
    expect(seq[w1Index].groupTotal, 1,
        reason: '本组只有 w_1 答错，这条轨道就 1 个词');
    final firstEn2Ch = seq.firstWhere((e) => e.step == 'En2Ch');
    expect(firstEn2Ch.trackName, '新词测评');
    expect(firstEn2Ch.groupTotal, batchSize, reason: '测评环节整组同属一条轨道');
    // 第 2 组没人答错：汉译英只有一条轨道，分母就是整组词数
    final secondBatchCh2En = seq.firstWhere((e) => e.step == 'Ch2En' && e.groupNo == 2);
    expect(secondBatchCh2En.trackName, '新词答对');
    expect(secondBatchCh2En.groupTotal, batchSize);
  });

  test('两轨道走不同环节：各按自己的轨道计数（答对组与测评环节同名）', () async {
    // 配置：测评 英译汉；答对组 英译汉（与测评环节同名！）；答错组 汉译英
    for (final c in [
      (group: 'check', step: 'En2Ch'),
      (group: 'correct', step: 'En2Ch'),
      (group: 'wrong', step: 'Ch2En'),
    ]) {
      await db.into(db.userStudySteps).insert(UserStudyStep(
            userId: testUser.id,
            scope: 'new',
            group: c.group,
            studyStep: c.step,
            seq: 0,
            state: 'Active',
            createTime: AppClock.now(),
            updateTime: AppClock.now(),
          ));
    }

    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    // 新词轨道：答对 → [英译汉, 英译汉, 小结]；答错 → [英译汉, 汉译英, 小结]
    const rightTrack = ['En2Ch', 'En2Ch', 'List'];
    const wrongTrack = ['En2Ch', 'Ch2En', 'List'];
    const wrongWordId = 'w_1';

    final seq = <({String wordId, int groupNo, int stepIndex, String step, String trackName, int position, int total})>[];
    var guard = 0;
    while (guard++ < 100) {
      final res = await studyBo.getWord(false, false);
      final data = res.data!;
      if (data.finished || data.learningWord == null) break;
      if (data.progress != null && data.progress![1] == 0) {
        await studyBo.completeListStepForCurrentBatch();
        continue;
      }
      final wordId = data.learningWord!.word.id!;
      // 只有 w_1 在测评环节答错；用各自轨道取真实环节名（同一个 stepIndex 可能是不同环节）
      final track = wordId == wrongWordId ? wrongTrack : rightTrack;
      final step = track[data.stepIndex];
      final progress =
          await studyBo.getBatchPhaseProgress(wordId: wordId, step: step);
      seq.add((
        wordId: wordId,
        groupNo: progress!.groupNo,
        stepIndex: data.stepIndex,
        step: step,
        trackName: progress.trackName,
        position: progress.position,
        total: progress.total,
      ));
      await studyBo.getWord(false, true,
          fsrsRating: wordId == wrongWordId && data.stepIndex == 0
              ? FsrsRating.again
              : FsrsRating.good);
    }

    // 只看第 1 组（本文件今日共 20 词，第 2 组无人答错）
    final group1 = seq.where((e) => e.groupNo == 1).toList();

    // 调度：整组横向混排，不按轨道分组 —— 答错的 w_1 组内序号最靠前，先做它的汉译英
    final second = group1.where((e) => e.stepIndex == 1).toList();
    expect(second.first.wordId, wrongWordId);

    // 测评环节：整组同轨道，顺位 1..10
    final assess = group1.where((e) => e.stepIndex == 0).toList();
    expect(assess.map((e) => e.trackName).toSet(), {'新词测评'});
    expect(assess.map((e) => e.position).toList(),
        List.generate(batchSize, (i) => i + 1));
    expect(assess.every((e) => e.total == batchSize), true);

    // 第二环节：两条轨道各走各的环节、各数各的词数
    final wrong = second.where((e) => e.trackName == '新词答错').toList();
    expect(wrong.map((e) => e.wordId).toList(), [wrongWordId]);
    expect(wrong.single.step, 'Ch2En');
    expect(wrong.single.position, 1);
    expect(wrong.single.total, 1);

    final right = second.where((e) => e.trackName == '新词答对').toList();
    expect(right.length, batchSize - 1);
    expect(right.every((e) => e.step == 'En2Ch'), true,
        reason: '答对组配的就是英译汉，与测评同名也不能被误判成测评环节');
    expect(right.map((e) => e.position).toList(),
        List.generate(batchSize - 1, (i) => i + 1));
    expect(right.every((e) => e.total == batchSize - 1), true);
  });

  test('小结标红只认"测评答错"：后续环节答错不参与', () async {
    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    // w_1 测评答错；w_2 测评答对、但汉译英答错
    await playWholeDay(wrongOnceWordId: 'w_1', wrongAtCh2EnWordId: 'w_2');

    // 前提校验：w_2 确实在今天留下过 again 日志，否则本用例会空转
    final w2Logs = await db.learningLogsDao.getHistory(testUser.id, 'w_2');
    expect(
        w2Logs.any((l) =>
            l.rating == FsrsRating.again.value &&
            !l.createTime.isBefore(AppClock.today())),
        true,
        reason: 'w_2 应在汉译英环节留下今天的 again 日志');

    final batchWordIds = [for (int i = 1; i <= batchSize; i++) 'w_$i'];
    final wrongIds = await studyBo.getTodayWrongWordIds(batchWordIds);

    expect(wrongIds, {'w_1'},
        reason: '标红口径 = 当天首条评分，与「新词答错」轨道一致；w_2 是汉译英答错，测评答对，不标红');
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

  test('轨道内进度指示与出题顺序一致（第 N 组 · 轨道 · 环节 x/y）', () async {
    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    final seq = await playWholeDay(wrongOnceWordId: 'w_1');

    // 测评环节：整组同属一条轨道，顺位恰好 1..10
    final en2Ch1 = seq.where((e) => e.step == 'En2Ch' && e.groupNo == 1).toList();
    expect(en2Ch1.map((e) => e.trackName).toSet(), {'新词测评'});
    expect(en2Ch1.map((e) => e.groupPosition).toList(),
        List.generate(batchSize, (i) => i + 1));
    expect(en2Ch1.every((e) => e.groupTotal == batchSize), true);

    // 汉译英：两条轨道各自从 1 数到自己那条轨道的词数（不是共用整组队列）
    final ch2En1 = seq.where((e) => e.step == 'Ch2En' && e.groupNo == 1).toList();
    final wrongTrack = ch2En1.where((e) => e.trackName == '新词答错').toList();
    final rightTrack = ch2En1.where((e) => e.trackName == '新词答对').toList();
    expect(wrongTrack.map((e) => e.wordId).toList(), ['w_1'],
        reason: '答错的 w_1 排在汉译英队列第 1 位');
    expect(wrongTrack.single.groupPosition, 1);
    expect(wrongTrack.single.groupTotal, 1);
    expect(rightTrack.length, batchSize - 1);
    expect(rightTrack.map((e) => e.groupPosition).toList(),
        List.generate(batchSize - 1, (i) => i + 1));
    expect(rightTrack.every((e) => e.groupTotal == batchSize - 1), true);

    // 第 2 组无人答错：汉译英只有一条轨道，进度 1..10
    final ch2En2 = seq.where((e) => e.step == 'Ch2En' && e.groupNo == 2).toList();
    expect(ch2En2.map((e) => e.trackName).toSet(), {'新词答对'});
    expect(ch2En2.every((e) => e.groupTotal == batchSize), true);
    expect(ch2En2.map((e) => e.groupPosition).toList(),
        List.generate(batchSize, (i) => i + 1));
  });

  test('分母是当前词所在轨道的词数：同组内的新词/旧词也各算各的', () async {
    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    // w_5 改造成复习词（同「复习词测评答错进入恢复环节」用例的口径）
    final yesterday = AppClock.today().subtract(const Duration(days: 1));
    await (db.update(db.learningWords)
          ..where((lw) => lw.userId.equals(testUser.id) & lw.wordId.equals('w_5')))
        .write(LearningWordsCompanion(
          isTodayNewWord: const Value(false),
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

    // 复习词答对：轨道为 [En2Ch, List]，汉译英环节不含它
    expect(seq.any((e) => e.wordId == 'w_5' && e.step == 'Ch2En'), false,
        reason: '复习词答对后不再走汉译英');

    // 测评环节：w_5 是旧词、其余 9 个是新词 → 两条轨道各自计数
    final en2Ch1 = seq.where((e) => e.step == 'En2Ch' && e.groupNo == 1).toList();
    final oldTrack = en2Ch1.where((e) => e.trackName == '旧词测评').toList();
    expect(oldTrack.map((e) => e.wordId).toList(), ['w_5']);
    expect(oldTrack.single.groupTotal, 1);
    final newTrack = en2Ch1.where((e) => e.trackName == '新词测评').toList();
    expect(newTrack.length, batchSize - 1);
    expect(newTrack.every((e) => e.groupTotal == batchSize - 1), true);

    // 汉译英：只剩「新词答对」一条轨道，分母是该轨道的 9 个词
    final ch2En1 = seq.where((e) => e.step == 'Ch2En' && e.groupNo == 1).toList();
    expect(ch2En1.map((e) => e.trackName).toSet(), {'新词答对'});
    expect(ch2En1.every((e) => e.groupTotal == batchSize - 1), true);
  });

  test('每组单词数：缺省 10，超出上限或当日计划词数时被压缩', () {
    expect(StudyConfig.fromJson({}).batchSize, batchSize, reason: '老配置无该字段时保持旧行为');
    expect(StudyConfig.fromJson({'batchSize': 999}).batchSize, StudyConfig.maxBatchSize);
    expect(StudyConfig.fromJson({'batchSize': 0}).batchSize, 1);

    final configured = StudyConfig(batchSize: 50);
    expect(configured.effectiveBatchSize(10), 50,
        reason: '每组单词数与当日计划量解耦，保持用户偏好的容器大小');
    expect(configured.effectiveBatchSize(50), 50);
    expect(configured.effectiveBatchSize(0), 50);
  });

  test('每组单词数可配置：设为当日计划词数时全天同属第 1 组', () async {
    // 用户在「高级学习设置」里把每组单词数调成 20（= 当日计划词数）
    final configured = testUser.copyWith(
        studyConfig: const Value<String?>(
            '{"autoPlayWord":false,"autoPlaySentence":false,"batchSize":20}'));
    await db.usersDao.saveUser(configured, true);
    Global.updateUserCache(configured);

    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    final seq = await playWholeDay();

    expect(seq.every((e) => e.step == 'List' || e.groupNo == 1), true,
        reason: '20 词一组时全天只有第 1 组，不再出现第 2 组');
    final en2Ch = seq.where((e) => e.step == 'En2Ch').toList();
    expect(en2Ch.length, wordTotal, reason: '整组一次走完 20 个词的测评');
    expect(en2Ch.every((e) => e.groupTotal == wordTotal), true,
        reason: '组内进度分母 = 用户设置的每组单词数');
  });

  test('calculateBatches: 严格按 batchId 边界对齐分块，禁止跨批次合并', () {
    final now = AppClock.now();
    // 模拟 15 个计划词 (batchId = 1) + 10 个加量词 (batchId = 2)
    final words = <LearningWord>[
      for (int i = 0; i < 15; i++)
        LearningWord(
          userId: 'test_user_id',
          wordId: 'w_$i',
          batchId: 1,
          learningOrder: i + 1,
          learnedTimes: 0,
          addTime: now,
          addDay: 1,
          todayLearnedTimes: 0,
          isTodayNewWord: true,
          isExtra: false,
          createTime: now,
          updateTime: now,
        ),
      for (int i = 15; i < 25; i++)
        LearningWord(
          userId: 'test_user_id',
          wordId: 'w_$i',
          batchId: 2,
          learningOrder: i + 1,
          learnedTimes: 0,
          addTime: now,
          addDay: 1,
          todayLearnedTimes: 0,
          isTodayNewWord: true,
          isExtra: true,
          createTime: now,
          updateTime: now,
        ),
    ];

    final batches = StudyBo.calculateBatches(words, 10);
    expect(batches.length, 3, reason: '应切为 3 个独立批次：10词、5词、加量10词');

    expect(batches[0].startIndex, 0);
    expect(batches[0].length, 10);
    expect(batches[0].groupNo, 1);

    expect(batches[1].startIndex, 10);
    expect(batches[1].length, 5);
    expect(batches[1].groupNo, 2);

    // 重点：加量词自成一组，绝对不能把前一组的 5 词跨 batchId 拼成 10 词
    expect(batches[2].startIndex, 15);
    expect(batches[2].length, 10);
    expect(batches[2].groupNo, 3);
  });

  test('非整除计划打卡后加量：getCurrentBatchCache 仅返回加量词且学完后无多余批次', () async {
    UserPrivilegeManager.isPremiumOverrideForTesting = true;
    addTearDown(() => UserPrivilegeManager.isPremiumOverrideForTesting = null);

    // 补充词书词量，确保加量能够抓取到 10 个新词
    final now = AppClock.now();
    for (int i = 21; i <= 35; i++) {
      final wordId = 'w_$i';
      await db.into(db.words).insert(Word(
            id: wordId,
            spell: 'word$i',
            popularity: 100,
            createTime: now,
            updateTime: now,
          ));
      await db.into(db.meaningItems).insert(MeaningItem(
            id: 'mim_$i',
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
            dictId: 'mock_dict',
            wordId: wordId,
            seq: i,
            unit: 0,
            createTime: now,
            updateTime: now,
          ));
    }

    // 1. 设置每日计划为 15 词
    final userWith15 = testUser.copyWith(wordsPerDay: 15);
    await db.usersDao.saveUser(userWith15, true);
    Global.updateUserCache(userWith15);

    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    // 2. 学完全部 15 个计划词
    int guard = 0;
    while (guard++ < 200) {
      final res = await studyBo.getWord(false, false);
      final data = res.data!;
      if (data.finished || data.learningWord == null) break;

      if (data.progress != null && data.progress![1] == 0) {
        final listRes = await studyBo.completeListStepForCurrentBatch();
        expect(listRes.success, true);
        continue;
      }

      await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
    }

    // 3. 点击「再来一组」（加量追加一组，即 10 个词）
    final addRes = await studyBo.prepareExtraStudy(count: 10);
    expect(addRes.success, true);
    expect(addRes.data, 10);

    // 4. 验证 getCurrentBatchCache 只包含新加量的 10 个词，不含今天之前学过的 15 个计划词
    final batchCache = await studyBo.getCurrentBatchCache();
    expect(batchCache.length, 10, reason: '加量批次应恰好包含 10 个加量词');
    final batchCacheWordIds = batchCache.map((w) => w.word.id).toList();
    for (int i = 1; i <= 15; i++) {
      expect(batchCacheWordIds.contains('w_$i'), false,
          reason: '今天之前学过的计划词 w_$i 绝不能混入加量批次');
    }

    // 5. 学完这一组加量词
    guard = 0;
    while (guard++ < 200) {
      final res = await studyBo.getWord(false, false);
      final data = res.data!;
      if (data.finished || data.learningWord == null) break;

      if (data.progress != null && data.progress![1] == 0) {
        final listRes = await studyBo.completeListStepForCurrentBatch();
        expect(listRes.success, true);
        continue;
      }

      await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
    }

    // 6. 验证学完该组后全部完成，不会再多出一组单词
    final afterBatch = await studyBo.getCurrentBatchCache();
    expect(afterBatch.isEmpty, true, reason: '学完加量的一组后直接结束，绝不产生碎片批次');

    final finalWordRes = await studyBo.getWord(false, false);
    expect(finalWordRes.data?.finished, true,
        reason: '按道理学完加量的一组就学完了，应标志 finished = true');
  });
}

