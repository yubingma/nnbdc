import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  late StudyBo studyBo;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async {
        return [];
      },
    );
  });

  test('复现线上用户 6db975f9c8bc4e159d9381cac3067486 掌握后流转异常', () async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    studyBo = StudyBo();
    StudyCacheManager().clear();

    final userId = '6db975f9c8bc4e159d9381cac3067486';
    AppClock.setClock(FakeClock(DateTime(2026, 10, 18, 22, 57, 10)));
    addTearDown(() {
      AppClock.reset();
    });
    final now = AppClock.now();
    testUser = User(
      id: userId,
      userName: 'ap_494c6e1b864c4480',
      password: '',
      nickName: '言 阿',
      email: 'bpvn2hhtm8@privaterelay.appleid.com',
      gameScore: 0,
      dakaScore: 0,
      learnedDays: 20,
      learningFinished: false,
      inviteAwardTaken: false,
      isSuperAdmin: false,
      isAdmin: false,
      isInputor: false,
      cowDung: 0,
      throwDiceChance: 0,
      wordsPerDay: 100,
      dakaDayCount: 17,
      masteredWordsCount: 360,
      maxContinuousDakaDayCount: 0,
      continuousDakaDayCount: 0,
      todayStudyStarted: true,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      lastLearningDate: AppClock.today(),
      createTime: now,
      updateTime: now,
      studyConfig: '{"autoPlayWord":true,"autoPlaySentence":false,"showAnswersDirectly":true,"enableAllWrong":false,"autoJumpAfterCorrectCh2En":false,"autoJumpAfterCorrectEn2Ch":false,"autoJumpAfterCorrectChSentence2En":false,"autoJumpAfterCorrectEnSentence2Ch":false,"asrPassRule":"ONE","enableWordImage":true,"preferKeyboardInSpelling":false,"distractorStrategy":"RecentlyLearned","mixWithOthersForIos":false,"showWordDetailAfterCorrect":false,"minNewWordsPerDay":0,"batchSize":20,"hideGroupStepHint":false}',
    );
    await db.usersDao.saveUser(testUser, false);
    Global.currentUserId = userId;
    Global.updateUserCache(testUser);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Prefs.write('currentUserId', userId);

    // 环节步骤
    await db.into(db.userStudySteps).insert(UserStudyStep(
      userId: userId, scope: 'new', group: 'check', studyStep: 'En2Ch', seq: 0, state: 'Active', createTime: now, updateTime: now));
    await db.into(db.userStudySteps).insert(UserStudyStep(
      userId: userId, scope: 'new', group: 'correct', studyStep: 'Ch2En', seq: 0, state: 'Active', createTime: now, updateTime: now));
    await db.into(db.userStudySteps).insert(UserStudyStep(
      userId: userId, scope: 'new', group: 'wrong', studyStep: 'Ch2En', seq: 0, state: 'Active', createTime: now, updateTime: now));
    await db.into(db.userStudySteps).insert(UserStudyStep(
      userId: userId, scope: 'review', group: 'check', studyStep: 'En2Ch', seq: 0, state: 'Active', createTime: now, updateTime: now));
    await db.into(db.userStudySteps).insert(UserStudyStep(
      userId: userId, scope: 'review', group: 'wrong', studyStep: 'Ch2En', seq: 0, state: 'Active', createTime: now, updateTime: now));

    // 读取完整 json 数据
    final jsonStr = await File('/Volumes/ssd/ppdc/tmp/user_data_full.json').readAsString();
    final data = jsonDecode(jsonStr);
    final lws = (data['lws'] as List);
    final masteredWordIds = (data['mastered'] as List).map((e) => e.toString()).toSet();
    final words = (data['words'] as List);
    final meaningItems = (data['meaning_items'] as List);
    final logs = (data['logs'] as List);

    // 插入已掌握词书
    final masteredDictId = '943801f94edf4fb0b6980b5564787e71';
    await db.into(db.dicts).insert(Dict(
      id: masteredDictId, name: '已掌握', wordCount: masteredWordIds.length, isShared: false, isReady: true,
      ownerId: userId, visible: true, editable: false, deletable: false, createTime: now, updateTime: now));
    for (final wid in masteredWordIds) {
      await db.into(db.dictWords).insert(DictWord(
        dictId: masteredDictId, wordId: wid, seq: 1, unit: 0, createTime: now, updateTime: now));
    }

    // 插入当前词书
    final currentDictId = '282';
    await db.into(db.dicts).insert(Dict(
      id: currentDictId, name: '《走遍美国》(第一册).dict', wordCount: 729, isShared: false, isReady: true,
      ownerId: 'sys', visible: true, editable: false, deletable: false, createTime: now, updateTime: now));
    await db.into(db.learningDicts).insert(LearningDict(
      userId: userId, dictId: currentDictId, isPrivileged: true, fetchMastered: false, sortAlg: 'ORIGINAL', createTime: now, updateTime: now));

    // 插入 words
    for (final wStr in words) {
      final parts = (wStr as String).split('|');
      final wid = parts[0];
      final spell = parts.length > 1 ? parts[1] : '';
      final pronounce = parts.length > 2 ? parts[2] : '';
      final shortDesc = parts.length > 3 ? parts[3] : '';
      final americaPronounce = parts.length > 4 ? parts[4] : '';
      final britishPronounce = parts.length > 5 ? parts[5] : '';
      await db.into(db.words).insert(Word(
        id: wid, spell: spell, pronounce: pronounce, shortDesc: shortDesc, americaPronounce: americaPronounce, britishPronounce: britishPronounce, popularity: 0, createTime: now, updateTime: now));
    }

    // 插入 learning_word（过滤出今天真正的 100 个词）
    final staleIds = {'2020','25731','1271','35722','40442','18093','25735','2906','1310','5169','3163'};
    for (final w in lws) {
      final wid = w['wordId'];
      final isStale = staleIds.contains(wid);
      await db.into(db.learningWords).insert(LearningWord(
        userId: userId,
        wordId: wid,
        addDay: w['addDay'] ?? 0,
        addTime: DateTime.fromMillisecondsSinceEpoch(w['addTime']),
        lastLearningDate: w['lastLearningDate'] != null ? DateTime.fromMillisecondsSinceEpoch(w['lastLearningDate']) : null,
        learningOrder: isStale ? 0 : w['learningOrder'],
        batchId: isStale ? 0 : w['batchId'],
        isExtra: w['isExtra'] ?? false,
        stability: w['stability']?.toDouble(),
        difficulty: w['difficulty']?.toDouble(),
        elapsedDays: w['elapsedDays'],
        scheduledDays: w['scheduledDays'],
        reps: w['reps'],
        lapses: w['lapses'],
        state: w['state'] ?? 0,
        isTodayNewWord: w['isTodayNewWord'] ?? false,
        learnedTimes: w['learnedTimes'] ?? 0,
        todayLearnedTimes: isStale ? 0 : (w['todayLearnedTimes'] ?? 0),
        createTime: DateTime.fromMillisecondsSinceEpoch(w['createTime']),
        updateTime: DateTime.fromMillisecondsSinceEpoch(w['updateTime']),
      ));
    }

    // 插入 meaning_items
    for (final mStr in meaningItems) {
      final parts = (mStr as String).split('\t');
      final mid = parts[0];
      final wid = parts[1];
      final ciXing = parts.length > 2 ? parts[2] : '';
      final meaning = parts.length > 3 ? parts[3] : '';
      final did = parts.length > 4 ? parts[4] : '0';
      await db.into(db.meaningItems).insert(MeaningItem(
        id: mid,
        wordId: wid,
        ciXing: ciXing,
        meaning: meaning,
        dictId: did,
        popularity: 0,
        ownerId: '',
        createTime: now,
        updateTime: now,
      ));
    }

    // 插入 learning_logs
    for (final lg in logs) {
      await db.into(db.learningLogs).insert(LearningLog(
        id: Util.uuid(),
        userId: userId,
        wordId: lg['wordId'],
        stability: 1.0,
        difficulty: 5.0,
        rating: lg['rating'],
        elapsedDays: lg['elapsedDays'],
        scheduledDays: lg['scheduledDays'],
        createTime: DateTime.fromMillisecondsSinceEpoch(lg['createTime']),
        updateTime: DateTime.fromMillisecondsSinceEpoch(lg['createTime']),
      ));
    }

    print('👉 步骤1：直接测试 StudyBo().getWord(true, true, currentWordId: "6544")...');
    try {
      final res = await studyBo.getWord(true, true, currentWordId: '6544');
      final lw = res.data?.learningWord;
      print('getWord 成功: wordId=${lw?.word.id}, stepIndex=${res.data?.stepIndex}');
      print('otherWords=${res.data?.otherWords?.map((w)=>"${w.id}:${w.spell}").toList()}');

      // 模拟 handleWord 中的完整逻辑
      print('👉 步骤2：模拟 handleWord...');
      WordVo word = res.data!.learningWord!.word;
      if (word.spell.isEmpty) {
        final local = await db.wordsDao.getWordById(word.id!);
        print('local word: ${local?.spell}');
        if (local != null) {
          word.spell = local.spell;
        }
      }
    } catch (e, st) {
      print('🔥 捕获到异常: $e\n$st');
    }
  });
}

class FakeBuildContext extends Fake implements BuildContext {
  @override
  bool get mounted => false;
}
