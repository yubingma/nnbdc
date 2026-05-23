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
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 手写 MockAsr，捕获并拦截所有的原生方法
class MockAsr implements Asr {
  final AsrState _state = AsrState.initialized;
  final List<Function(AsrState)> _stateListeners = [];

  @override
  AsrState get state => _state;

  @override
  bool get isPreloaded => true;

  @override
  bool get permissionGranted => true;

  @override
  set permissionGranted(bool value) {}

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
  Future<void> startAsr(AsrLanguage language, {List<String>? phrases}) async {}

  @override
  Future<void> stopAsr() async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> reset() async {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// 手写 MockAudioPlayer，捕获并拦截原生语音的方法
class MockAudioPlayer implements ja.AudioPlayer {
  @override
  bool get playing => false;

  @override
  ja.ProcessingState get processingState => ja.ProcessingState.idle;

  @override
  Stream<ja.PlayerState> get playerStateStream => Stream.value(ja.PlayerState(false, ja.ProcessingState.idle));

  @override
  Duration? get duration => null;

  @override
  Duration get position => Duration.zero;

  @override
  Stream<Duration> get positionStream => Stream.value(Duration.zero);

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration? position, {int? index}) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeed(double speed) async {}

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

void main() {
  // 确保 Flutter 绑定初始化（针对测试环境下的 MethodChannel 等服务模拟）
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  final now = AppClock.now();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async {
        return [];
      },
    );
    // 拦截 just_audio 平台的底层 MethodChannel，返回成功数据
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        return {};
      },
    );
    // 拦截 audio_session 平台的底层 MethodChannel，返回成功数据
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  setUp(() async {
    SoundUtil.audioSessionConfigured = true;
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

    // 插入学习步骤配置: 1个答题环节(En2Ch)
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'En2Ch',
          seq: 0,
          state: 'Active',
          createTime: now,
          updateTime: now,
        ));

    // 生成 Mock 词书和映射
    var dictId = 'mock_dict_1';
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
          createTime: now,
          updateTime: now,
        ));

    // 插入 1 个单词供学习
    var wordId = 'word_1';
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
          meaning: '苹果',
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

    await db.into(db.learningWords).insert(LearningWord(
          userId: testUser.id,
          wordId: wordId,
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

  tearDown(() async {
    await db.close();
  });

  test('BdcNotifier - loadData 和提示词状态变更单元测试', () async {
    final mockAsr = MockAsr();
    final mockAudioPlayer = MockAudioPlayer();

    final container = ProviderContainer(
      overrides: [
        asrProvider.overrideWithValue(mockAsr),
        bdcAudioPlayerProvider.overrideWithValue(mockAudioPlayer),
      ],
    );
    addTearDown(container.dispose);

    // 1. 初始状态：dataLoaded 应为 false，单词应为 null
    var state = container.read(bdcNotifierProvider);
    expect(state.dataLoaded, false);
    expect(state.word, null);

    // 2. 调用 loadData 加载数据
    final notifier = container.read(bdcNotifierProvider.notifier);
    final context = FakeBuildContext();
    await notifier.loadData(context);

    // 验证数据正确加载
    state = container.read(bdcNotifierProvider);
    expect(state.dataLoaded, true);
    expect(state.word != null, true);
    expect(state.word!.spell, 'apple');
    expect(state.studyStep, 'En2Ch');

    // 3. 验证提示词逻辑 (giveALittleHint)
    expect(state.hintTapCount, 0);
    notifier.giveALittleHint();

    state = container.read(bdcNotifierProvider);
    expect(state.hintTapCount, 1);
    expect(state.wordWrapper!.hintLetterCount, 1);

    // 4. 验证手写板状态翻转 (toggleHandwritingBoard)
    expect(state.showHandwritingBoard, false);
    notifier.toggleHandwritingBoard();

    state = container.read(bdcNotifierProvider);
    expect(state.showHandwritingBoard, true);

    // 等待所有后台异步任务（例如 StudyBo 里的单词拼写预获取）在数据库关闭前执行完毕，防止出现 Can't re-open database 警告
    await Future.delayed(const Duration(milliseconds: 100));
  });
}
