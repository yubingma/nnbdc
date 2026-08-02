import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nnbdc/services/study_cache_manager.dart';

/// 手写 MockAsr,捕获并拦截原生方法
class MockAsr implements Asr {
  final AsrState _state = AsrState.initialized;
  final List<Function(AsrState)> _stateListeners = [];

  int startAsrCallCount = 0;
  int stopAsrCallCount = 0;

  @override
  AsrState get state => _state;

  @override
  bool get isPreloaded => true;

  @override
  bool get permissionGranted => true;

  @override
  set permissionGranted(bool value) {}

  @override
  AsrLanguage? get currentLanguage => null;

  @override
  Future<void> updateLanguage(AsrLanguage language) async {}

  @override
  void addStateListener(Function(AsrState) listener) {
    _stateListeners.add(listener);
  }

  @override
  void removeStateListener(Function(AsrState) listener) {
    _stateListeners.remove(listener);
  }

  @override
  Future<void> initAsr(void Function(dynamic)? asrListener) async {}

  @override
  Future<void> preloadModels() async {}

  @override
  Future<void> startAsr(AsrLanguage language, {List<String>? phrases, bool playHintSound = true}) async {
    startAsrCallCount++;
  }

  @override
  Future<String?> stopAsr() async {
    stopAsrCallCount++;
    return null;
  }

  @override
  Future<void> startMicrophone() async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> reset() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBuildContext implements BuildContext {
  @override
  bool get mounted => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 例句中英 (ChSentence2En) 发音纠错测试:
/// 中文用户发音不准时,ASR 常把单词切分成多个近音词
/// (如 discipline → "this plan"/"teasplane"),纠错应合并回目标词。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  final now = AppClock.now();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => [],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async => {},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (MethodCall methodCall) async => null,
    );
  });

  setUp(() async {
    StudyAudioSessionController.instance.audioSessionConfigured = true;
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);

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
      wordsPerDay: 5,
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
    Global.currentUserId = 'test_user_id';
    Global.updateUserCache(testUser);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Prefs.write('currentUserId', 'test_user_id');

    // 基础词书与单词数据(loadData 依赖)
    var dictId = 'mock_dict_corr';
    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '测试词书',
          wordCount: 10,
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
          id: 'word_corr_base',
          spell: 'discipline',
          popularity: 100,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.meaningItems).insert(MeaningItem(
          id: 'mim_corr_base',
          wordId: 'word_corr_base',
          dictId: Global.commonDictId,
          ciXing: 'n.',
          meaning: '纪律',
          popularity: 100,
          ownerId: Global.sysUserId,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.dictWords).insert(DictWord(
          dictId: dictId,
          wordId: 'word_corr_base',
          seq: 1,
          unit: 0,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.learningWords).insert(LearningWord(
          userId: testUser.id,
          wordId: 'word_corr_base',
          addTime: now,
          addDay: 1,
          batchId: 1,
          lastLearningDate: AppClock.today(),
          stability: 0.0,
          isTodayNewWord: true,
          learnedTimes: 0,
          todayLearnedTimes: 0,
          learningOrder: 1,
          createTime: now,
          updateTime: now,
        ));
  });

  Future<(BdcNotifier, MockAsr)> setupSentence2En(String sentenceEn, String sentenceCh) async {
    // 学习步骤: En2Ch(seq 0) 基础 + ChSentence2En(seq 1) 例句中英
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'En2Ch',
          seq: 0,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'ChSentence2En',
          seq: 1,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));
    // 将基础词的今日学习次数置为 1,使 StudyBo 计算 stepIndex = 1(例句步骤)
    await (db.update(db.learningWords)..where((lw) => lw.userId.equals(testUser.id)))
        .write(LearningWordsCompanion(todayLearnedTimes: const Value(1)));

    // 例句
    await db.into(db.sentences).insert(Sentence(
          id: 'snt_corr',
          english: sentenceEn,
          chinese: sentenceCh,
          englishDigest: sentenceEn,
          partOfSpeech: '',
          theType: 'tts',
          handCount: 0,
          footCount: 0,
          authorId: 'sys',
          ownerId: 'sys',
          meaningItemId: 'mim_corr_base',
          wordMeaning: '纪律',
          createTime: now,
          updateTime: now,
        ));
    StudyCacheManager().clear();

    final mockAsr = MockAsr();
    StudyAudioSessionController.instance.debugSetAsrForTesting(mockAsr);
    PlatformUtils.asrSupportedOverride = true;
    addTearDown(() => PlatformUtils.asrSupportedOverride = null);

    final container = ProviderContainer(
      overrides: [
        asrProvider.overrideWithValue(mockAsr),
      ],
    );
    addTearDown(() => container.dispose());

    final notifier = container.read(bdcNotifierProvider.notifier);
    await notifier.loadData(FakeBuildContext());
    expect(container.read(bdcNotifierProvider).studyStep, 'ChSentence2En');
    return (notifier, mockAsr);
  }

  /// 在 PTT 按住状态下模拟一次 ASR 识别结果,返回纠错后的答案区文本
  Future<String> simulateAsrCorrection(BdcNotifier notifier, MockAsr mockAsr, String asrText) async {
    notifier.startPttAsr();
    for (var i = 0; i < 20 && mockAsr.startAsrCallCount < 1; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    await notifier.onAsrResult(jsonEncode({
      'best': asrText,
      'candidates': [asrText],
      'isFinal': false,
    }));
    final result = notifier.sentenceAnswerController.text.trim().toLowerCase();
    await notifier.stopPttAsr();
    await Future.delayed(const Duration(milliseconds: 50));
    return result;
  }

  test('用例1: 目标 good discipline, ASR 结果 good this plan → 纠正为 good discipline', () async {
    final (notifier, mockAsr) = await setupSentence2En(
      'Good discipline is essential for success in any organization.',
      '良好的纪律对任何组织的成功都至关重要。',
    );
    final result = await simulateAsrCorrection(notifier, mockAsr, 'good this plan');
    expect(result, 'good discipline');
  });
}
