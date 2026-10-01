import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/learning_service.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bdc_notifier_test.dart' show MockAsr, FakeBuildContext;

/// 「已答出的释义」在环节之间的继承边界。
///
/// 用户反馈：从测评环节进入「新词答错」环节时，前一个环节答对的释义被直接渲染成绿色，
/// 看起来像答案被提前揭晓。
///
/// 根因：呈现新词时无条件把上一轮缓存的命中释义并进当前题的 wrapper，没有按环节序号区分，
/// 于是上一环节答对过的释义会在新环节一开局就渲染成绿色。
/// 修复：把"继承已命中释义"收进 _restoreWordState 的**同环节**分支（按 stepIndex 判定），
/// 换环节一律从零开始。
///
/// 顺带确认了一件事：答错（again）时该词的答题态会被主动清掉（这是修"卡住"时定的规则），
/// 因此**同环节重练也不会继承**绿色释义，同样从零开始答 —— 两个用例一起把这个口径钉住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;

  const String dictId = 'mock_dict_1';
  const String wordId = 'word_1';

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall call) async => {},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (MethodCall call) async => null,
    );
  });

  setUp(() async {
    AppClock.setClock(FakeClock(DateTime(2026, 5, 20, 8, 0)));
    ThrottledDbSyncService().reset();
    StudyCacheManager().clear();
    StudyAudioSessionController.instance.audioSessionConfigured = true;
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);

    final now = AppClock.now();
    testUser = User(
      id: 'meaning_carry_user',
      userName: 'meaning_carry_user',
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
      wordsPerDay: 1,
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

    for (final group in ['mock_dict_mastered', 'mock_dict_raw']) {
      await db.into(db.dicts).insert(Dict(
            id: group,
            name: group,
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
    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '释义继承测试词书',
          wordCount: 1,
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
    await db.into(db.words).insert(Word(
          id: wordId,
          spell: 'apple',
          popularity: 100,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.meaningItems).insert(MeaningItem(
          id: 'mim_1',
          wordId: wordId,
          dictId: Global.commonDictId,
          ciXing: 'n.',
          meaning: '苹果;萍果',
          popularity: 100,
          ownerId: Global.sysUserId,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.dictWords).insert(DictWord(
          dictId: dictId,
          wordId: wordId,
          seq: 1,
          unit: 0,
          createTime: now,
          updateTime: now,
        ));
  });

  tearDown(() async {
    ThrottledDbSyncService().reset();
    StudyCacheManager().clear();
    AppClock.reset();
    await Future.delayed(const Duration(milliseconds: 30));
    await db.close();
    MyDatabase.setInstanceForTesting(null);
  });

  test('换环节后不继承上一环节已答出的释义（新环节从零开始）', () async {
    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    final mockAsr = MockAsr();
    final container = ProviderContainer(overrides: [
      asrProvider.overrideWithValue(mockAsr),
    ]);
    final keepAlive = container.listen(bdcNotifierProvider, (_, __) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    var state = container.read(bdcNotifierProvider);
    expect(state.word!.id, wordId);
    expect(state.currentGetWordResult!.stepIndex, 0, reason: '起点是测评环节');

    // 把测评答对：缓存里会留下"已命中释义"
    notifier.acceptAnswerForTesting(FsrsRating.good);
    await notifier.getNextWord(true, fsrsRating: FsrsRating.good);

    state = container.read(bdcNotifierProvider);
    expect(state.word!.id, wordId, reason: '同一个词进入下一环节');
    expect(state.currentGetWordResult!.stepIndex, greaterThan(0),
        reason: '已进入下一环节');
    expect(
      state.wordWrapper!.asrMatchedMeaningItemParts,
      isEmpty,
      reason: '换环节后新题必须从零开始：不得把上一环节答出的释义渲染成绿色',
    );
  });

  test('同环节重练也不继承已答出的释义（答错时答题态已被清掉）', () async {
    final prep = await LearningService.prepareTodayStudy(true);
    expect(prep.success, true);

    final mockAsr = MockAsr();
    final container = ProviderContainer(overrides: [
      asrProvider.overrideWithValue(mockAsr),
    ]);
    final keepAlive = container.listen(bdcNotifierProvider, (_, __) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());

    expect(container.read(bdcNotifierProvider).currentGetWordResult!.stepIndex, 0);

    // 答错：留在本环节，缓存里留下的是"同一环节"的答题态
    notifier.acceptAnswerForTesting(FsrsRating.again);
    await notifier.getNextWord(true, fsrsRating: FsrsRating.again);

    final cached = container.read(bdcNotifierProvider).wordUIStates[wordId];
    expect(cached, isNull,
        reason: '答错时该词的答题态会被清掉（修"卡住"时定的规则），'
            '因此重练不会继承上一轮的绿色释义，而是从零开始答');
  });
}
