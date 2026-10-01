// ignore_for_file: avoid_print

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

/// 「本组环节进度」指示器的口径探针。
///
/// 用户反馈：一组 10 个词，测评环节第 1 个词点「不认识」，进到第 2 个词仍显示 1/10。
///
/// 根因是原来的分子按"已走完本环节的词数"算：答错的词留在本环节重练、不计入完成，
/// 于是第一个词答错后分子卡在 1 不动。
///
/// 现在分子改为"本环节已出过题的词数"，由 PhasePresentationTracker 单独记录
///（同一环节里"答错待重练"与"还没轮到"的词在 learning_word 上完全同态，仅凭库里数据无法区分），
/// 于是序号随出题逐个前进，且错词重练不重复计数、分子被夹在 [1, 分母] 内。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late StudyBo studyBo;

  const int wordTotal = 10;
  const String userId = 'phase_indicator_user';

  /// 依次取词并读出「本环节进度」，返回 (词 id, 进度字符串, 位置, 分母)
  Future<({String wordId, int position, int total, String trackName, bool isRetry})> nextWord() async {
    final res = await studyBo.getWord(false, false);
    expect(res.success, true);
    final data = res.data!;
    final wordId = data.learningWord!.word.id!;
    final progress = await studyBo.getBatchPhaseProgress(
      wordId: wordId,
      step: 'En2Ch',
      markPresentedWord: true, // 与学习页真实调用一致：呈现即记为已出题
    );
    expect(progress, isNotNull, reason: '当前词应能定位到本组本环节');
    return (
      wordId: wordId,
      position: progress!.position,
      total: progress.total,
      trackName: progress.trackName,
      isRetry: progress.isRetry,
    );
  }

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '.',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall call) async => [],
    );
  });

  setUp(() async {
    AppClock.setClock(FakeClock(DateTime(2026, 5, 20, 8, 0, 0)));
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    studyBo = StudyBo();
    StudyCacheManager().clear();

    final now = AppClock.now();
    final testUser = User(
      id: userId,
      userName: 'phase_user',
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
    Global.currentUserId = userId;
    Global.updateUserCache(testUser);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Prefs.write('currentUserId', userId);

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
            ownerId: userId,
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
          name: '进度指示测试词书',
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
          userId: userId,
          dictId: dictId,
          isPrivileged: false,
          fetchMastered: false,
          sortAlg: 'ORIGINAL',
          createTime: now,
          updateTime: now,
        ));

    for (var i = 1; i <= wordTotal; i++) {
      final wordId = 'w_$i';
      await db.into(db.words).insert(Word(
            id: wordId,
            spell: 'word$i',
            popularity: 100,
            createTime: now,
            updateTime: now,
          ));
      await db.into(db.meaningItems).insert(MeaningItem(
            id: 'mim_$wordId',
            wordId: wordId,
            dictId: Global.commonDictId,
            ciXing: 'n.',
            meaning: '含义$i',
            popularity: 100,
            ownerId: Global.sysUserId,
            createTime: now,
            updateTime: now,
          ));
      await db.into(db.dictWords).insert(DictWord(
            dictId: dictId,
            wordId: wordId,
            seq: i,
            unit: 0,
            createTime: now,
            updateTime: now,
          ));
    }
  });

  tearDown(() async {
    StudyCacheManager().clear();
    AppClock.reset();
    await db.close();
    MyDatabase.setInstanceForTesting(null);
  });

  test('测评首个词点不认识后，第二个词显示 2/10（序号随出题前进）', () async {
    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    final first = await nextWord();
    print('第 1 个词 ${first.wordId}：${first.trackName} ${first.position}/${first.total}');
    expect(first.position, 1);
    expect(first.total, wordTotal);
    expect(first.isRetry, isFalse, reason: '第一个词是本环节首次作答，不是重测');

    // 点「不认识」：评分 again，不推进该词环节索引
    await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);

    final second = await nextWord();
    print('第 2 个词 ${second.wordId}：${second.trackName} ${second.position}/${second.total}');
    expect(second.wordId, isNot(first.wordId), reason: '答错的词排到本环节队尾');
    expect(second.position, 2,
        reason: '分子按"本环节已出过题"计：见到第二个词就应前进到 2');
    expect(second.isRetry, isFalse, reason: '没答过的词不能被标成重测');
  });

  test('整组测评逐个点不认识：序号 1..10 逐个前进，分母恒为 10', () async {
    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    final positions = <int>[];
    for (var i = 1; i <= wordTotal; i++) {
      final word = await nextWord();
      positions.add(word.position);
      expect(word.total, wordTotal);
      await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
    }

    print('逐个点不认识的序号序列：$positions');
    expect(positions, List.generate(wordTotal, (i) => i + 1),
        reason: '每见到一个新词，序号都应前进一格');
  });

  test('错词重练时序号不跳号、不超过分母', () async {
    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    // 前两个词答错（留在本环节重练），后面 8 个答对（推进到下一环节）
    final wrongIds = <String>{};
    for (var i = 1; i <= wordTotal; i++) {
      final word = await nextWord();
      final wantWrong = i <= 2;
      if (wantWrong) wrongIds.add(word.wordId);
      await studyBo.getWord(false, true,
          fsrsRating: wantWrong ? FsrsRating.again : FsrsRating.good);
    }

    // 队尾重练第一个错词：它已占过一格，不重复计数；分母因 8 个词已离开本环节而收缩，
    // 分子必须跟着收敛，绝不能出现 11/10
    final retry = await nextWord();
    print('错词重练 ${retry.wordId}：${retry.trackName} ${retry.position}/${retry.total}');
    expect(wrongIds.contains(retry.wordId), isTrue, reason: '此时回来的应是答错待重练的词');
    expect(retry.position, lessThanOrEqualTo(retry.total), reason: '序号绝不能超过分母');
    expect(retry.position, wordTotal,
        reason: '错词前面已出过题，重练时仍占它当时的那一格（10/10），既不加倍也不超过分母');
    expect(retry.isRetry, isTrue,
        reason: '本环节答错后回到队尾再答一次的，必须被标成本环节重测');
  });
}
