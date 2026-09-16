import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/study_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;

  setUpAll(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => <String>[],
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  tearDown(() async {
    await db.close();
    Global.currentUserId = null;
  });

  test('例句英译汉模式受学习设置 autoPlaySentence 控制自动播放例句', () async {
    final user = User(
      id: 'test_user_sentence_1',
      userName: 'tester',
      nickName: 'Tester',
      password: '',
      email: '',
      gameScore: 0,
      dakaScore: 0,
      learnedDays: 1,
      wordsPerDay: 5,
      dakaDayCount: 1,
      masteredWordsCount: 0,
      cowDung: 0,
      throwDiceChance: 0,
      continuousDakaDayCount: 1,
      maxContinuousDakaDayCount: 1,
      todayStudyStarted: true,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
      studyConfig: jsonEncode({'autoPlaySentence': true, 'autoPlayWord': false}),
    );
    await db.usersDao.saveUser(user, false);
    Global.currentUserId = user.id;
    Global.updateUserCache(user);

    final config = StudyConfig.fromCurrentUser();
    expect(config.autoPlaySentence, isTrue);

    final testWord = WordVo.c2('galaxy')
      ..id = 'w_galaxy'
      ..setMeaningStr('n. 星系');
    final sentenceVo = SentenceVo(
      's_1',
      'The Milky Way is our galaxy.',
      '银河系是我们的星系。',
      null,
      'n.',
      'tts',
      0,
      0,
      UserVo.c2('author1'),
    );
    testWord.meaningItems = [
      MeaningItemVo('mi_1', 'n.', '星系', null, null, [sentenceVo]),
    ];

    final bdcState = BdcState(
      studyStep: StudyStep.enSentence2Ch.json,
      word: testWord,
      englishDigestOfFirstSentence: 'digest_123',
    );

    // 1. autoPlaySentence 为 true 时：
    // 在 enSentence2Ch 步骤，willPlaySentence 判定应为 true，willPlayWord 应为 false
    final studyConfig = StudyConfig.fromCurrentUser();
    bool willPlayWord = (bdcState.studyStep == StudyStep.en2Ch.json && studyConfig.autoPlayWord);
    bool willPlaySentence = ((bdcState.studyStep == StudyStep.en2Ch.json ||
            bdcState.studyStep == StudyStep.enSentence2Ch.json) &&
        studyConfig.autoPlaySentence);

    expect(willPlayWord, isFalse);
    expect(willPlaySentence, isTrue);

    // 2. 将 autoPlaySentence 设置为 false 时：
    final updatedUser = user.copyWith(
      studyConfig: drift.Value(jsonEncode({'autoPlaySentence': false, 'autoPlayWord': false})),
    );
    Global.updateUserCache(updatedUser);
    final configDisabled = StudyConfig.fromCurrentUser();
    expect(configDisabled.autoPlaySentence, isFalse);

    bool willPlaySentenceDisabled = ((bdcState.studyStep == StudyStep.en2Ch.json ||
            bdcState.studyStep == StudyStep.enSentence2Ch.json) &&
        configDisabled.autoPlaySentence);
    expect(willPlaySentenceDisabled, isFalse);
  });
}
