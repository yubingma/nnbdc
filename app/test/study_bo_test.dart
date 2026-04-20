import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:nnbdc/api/enum.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late User testUser;
  late StudyBo studyBo;
  final now = AppClock.now();

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

  setUp(() async {
    // 实例化一个存在内存中的 SQLite, 拥有完整的业务表结构和验证机制
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    studyBo = StudyBo();

    // 1. 生成 Mock User，每日计划是 5 个词
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
      lastLearningDate: now,
    );
    await db.usersDao.saveUser(testUser, false);

    // 塞进 Global 变量缓存
    Global.currentUserId = 'test_user_id';
    Global.updateUserCache(testUser);
    await GetStorage.init();
    GetStorage().write('currentUserId', 'test_user_id');

    // 生成学习步骤配置: 1个答题环节(En2Ch) + 1个浏览环节(List)
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'En2Ch',
          seq: 0,
          state: 'Active',
          createTime: now,
        ));
    await db.into(db.userStudySteps).insert(UserStudyStep(
          userId: testUser.id,
          studyStep: 'List',
          seq: 1,
          state: 'Active',
          createTime: now,
        ));

    // 2. 生成 Mock 词书和映射
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

    // 生成“已掌握”词书给用户
    await db.into(db.dicts).insert(Dict(
          id: 'mock_dict_mastered',
          name: '已掌握',
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

    await db.into(db.learningDicts).insert(LearningDict(
          userId: testUser.id,
          dictId: dictId,
          isPrivileged: false,
          fetchMastered: false,
          createTime: now,
          updateTime: now,
        ));

    // 3. 生成 5 个 Mock 词条到今天需要学习的列表中 (作为 batchId = 1，直接进入今天的学习池)
    for (int i = 1; i <= 5; i++) {
      var wordId = 'word_$i';
      await db.into(db.words).insert(Word(
            id: wordId,
            spell: 'apple_$i',
            popularity: 100,
            createTime: now,
            updateTime: now,
          ));
      
      // 为混淆选择提供释义
      await db.into(db.meaningItems).insert(MeaningItem(
            id: 'mim_$i',
            wordId: wordId,
            dictId: Global.commonDictId,
            ciXing: 'n.',
            meaning: 'apple juice $i',
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

      await db.into(db.learningWords).insert(LearningWord(
            userId: testUser.id,
            wordId: wordId,
            addTime: now,
            addDay: 1,
            batchId: 1, // <--- 这里是重点，batchId=1 代表这五个词是今天的批次候选
            lastLearningDate: now,
            stability: 0.0,
            isTodayNewWord: true,
            learnedTimes: 0,
            todayLearnedTimes: 0, // <--- 关键进度：今天学了多少个环节
            learningOrder: i,
            createTime: now,
            updateTime: now,
          ));
    }
  });

  tearDown(() async {
    await db.close();
  });

  group('StudyBo - 取下一个单词和学习流转逻辑测试', () {
    test('初始获取第一个单词: 进度为0，环节应为0 (En2Ch)', () async {
      // gotoNext=false 表示只是获取当前单词展示进度，不推进流程
      final result = await studyBo.getWord(false, false);

      expect(result.success, true);
      final wordResult = result.data!;
      expect(wordResult.finished, false);

      // 第一个词是 word_1，环节索引为 0 (对应 En2Ch)
      expect(wordResult.learningWord!.word.id, 'word_1');
      expect(wordResult.stepIndex, 0);

      // 这时刚开始学，进度应为 [0, 10] (5个词 * 2个环节)
      expect(wordResult.progress![0], 0);
      expect(wordResult.progress![1], 10);
    });

    test('推进一个环节(gotoNext=true)：正确叠加进度并跳到 List(或下一个词)', () async {
      // 第一次答对：gotoNext=true 会保存记录，增加 learnedTimes 和 todayLearnedTimes
      // 我们在此刻还可以给一个 FSRS 打分
      final result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.good);
      expect(result.success, true);

      // 为了看效果，我们在推进一步后获取现在该学哪个词。注意，刚才通过 gotoNext=true，
      // 其实 getWord 内部分两步：先用传进去的值推进(把当前 current 进度+1)，再去找下一次进度对应的事。
      // 它返回的值已经是"推导后的下一个"或者"处于List环节"。
      
      // 第一个词 word_1 的 todayLearnedTimes 会从 0 -> 1。
      // List 配置也是 1。一旦 List 它就会返回一个空的模式 (列表页面显示)。
      final nextWordResult = result.data!;

      // 这时候处于 List 模式时，getWord 实际上在内部构建的 Result 中，
      // 如果 isListStep 命中，它会强制使得 currentStepIndex 为 List 的索引，但这本身可能是刚推过的那个词的进度。
      // 所以我们直接看看库里的真实影响：
      var updatedWord1 = await (db.select(db.learningWords)..where((w) => w.wordId.equals('word_1'))).getSingle();

      expect(updatedWord1.todayLearnedTimes, 1);
      // 有了 fsrs rating, 所以 stability 有了一个基础初始值
      expect(updatedWord1.stability, greaterThan(0.0));

      // 因为 word_1 更新了 1 进度，今天它的优先度降低了，接下来应该推导到 word_2（它的进度为 0）
      expect(nextWordResult.learningWord!.word.id, 'word_2');
      expect(nextWordResult.stepIndex, 0);
    });

    test('标记完全掌握跳过逻辑: isWordMastered = true 时直接完成', () async {
      final result = await studyBo.getWord(true, true);
      expect(result.success, true);

      // 验证它确实落入了已掌握词库表
      var masteredRec = await (db.select(db.dictWords)..where((w) => w.wordId.equals('word_1') & w.dictId.equals('mock_dict_mastered'))).getSingleOrNull();
      expect(masteredRec, isNotNull);

      // 由于 word_1 被标记已掌握，如果接下来我们再拉下一个词去展示，就会自动跳过 word_1。
      final fetchNext = await studyBo.getWord(false, false);
      
      // 这个 fetchNext 获取到的不再是 word_1，而是 word_2！且进度因为 word_1 被视为完成，自动折合为 2 分进度(也就是 2/10 + ...)
      expect(fetchNext.data!.learningWord!.word.id, 'word_2');
      expect(fetchNext.data!.progress![0], greaterThanOrEqualTo(2));
    });

    test('答错 FsrsRating.again 时：自动加入错词表', () async {
      // 当前是 word_1，回答了 again
      final result = await studyBo.getWord(false, true, fsrsRating: FsrsRating.again);
      expect(result.success, true);

      // 验证是否已进入错词映射表 user_wrong_words
      var wrongRec = await (db.select(db.userWrongWords)..where((w) => w.wordId.equals('word_1'))).getSingleOrNull();
      expect(wrongRec, isNotNull);
    });

    test('模拟所有单词完成学习：跨越环节和提取完成状态', () async {
      // 我们用 update 强行把所有的词全都标记为学满今天次数
      for (int i = 1; i <= 5; i++) {
        var lw = await (db.select(db.learningWords)..where((w) => w.wordId.equals('word_$i'))).getSingle();
        await db.learningWordsDao.saveEntity(lw.copyWith(
          todayLearnedTimes: 2, // 达到总环节数(2)
          learnedTimes: 2,
        ), true);
      }

      // 这个时候如果再调 getWord
      final result = await studyBo.getWord(false, false);
      expect(result.success, true);
      expect(result.data!.finished, true); // 返回结束标记
    });
  });
}
