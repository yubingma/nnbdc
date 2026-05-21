import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/util/distractor_strategy.dart';
import 'package:nnbdc/util/study_config.dart';
import 'package:nnbdc/util/study_steps_service.dart';
import 'package:nnbdc/util/learning_service.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/util/oper_type.dart';
import 'package:drift/drift.dart';
import 'dart:async';
import 'dart:math';
import 'package:nnbdc/event/events.dart';
import 'package:nnbdc/util/fsrs.dart';
import 'package:nnbdc/util/analytics_util.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'word_bo.dart';
import 'package:nnbdc/util/date_utils.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'dart:convert';
import 'package:nnbdc/api/api.dart';

/// 业务对象（BO）：承载本地实现逻辑
class StudyBo {
  final StudyStepsService _studyStepsService = StudyStepsService();
  static final StudyBo _instance = StudyBo._internal();

  factory StudyBo() {
    return _instance;
  }

  StudyBo._internal();
  
  String? _lastPreGeneratedBatchHash;

  void _triggerAiStoryPreGeneration(List<String> wordSpells) {
    if (wordSpells.length < 5) return;
    
    // 生成一个简单的识别标志，防止重复请求同一批次
    final spells = List<String>.from(wordSpells)..sort();
    final batchHash = spells.join(',');
    if (batchHash == _lastPreGeneratedBatchHash) return;
    _lastPreGeneratedBatchHash = batchHash;

    Global.logger.d('触发 AI 短文预生成: $wordSpells, userId: ${Global.currentUserId}');
    unawaited(Api.client.generateAiShortStory(jsonEncode(wordSpells), Global.currentUserId!).then((res) {
      if (res.success) {
        Global.logger.d('AI 短文预生成成功');
      } else {
        Global.logger.w('AI 短文预生成失败: ${res.msg}');
      }
    }).catchError((e) {
      Global.logger.w('AI 短文预生成异常: $e');
    }));
  }

  static void clearUserCaches() {
    StudyCacheManager().clear();
  }

  static Future<Set<String>> getUserLearningWordIds(MyDatabase db, String userId) async {
    return StudyCacheManager().getLearningWordIds(db, userId);
  }

  Future<Result<List<int>>> prepareForStudy(bool addNewWordsIfNotEnough) async {
    try {
      Global.logger.d('开始准备学习单词...');
      final result = await LearningService.prepareTodayStudy(addNewWordsIfNotEnough);
      if (!result.success) {
        return result;
      }
      
      // 漏斗：进入背词界面，获取到背词数据（学习开始）
      AnalyticsUtil.trackStartStudy();

      // 同步到后端
      ThrottledDbSyncService().requestSync();

      return result;
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, operation: '准备学习单词');
      final result = Result<List<int>>("ERROR", "准备学习失败: ${e.toString()}", false);
      result.data = [0, 0];
      return result;
    }
  }

  Future<Result<List<UserStudyStepVo>>> getUserStudySteps() async {
    try {
      final steps = await _studyStepsService.getUserStudySteps();
      final result = Result<List<UserStudyStepVo>>("SUCCESS", "获取成功", true);
      result.data = steps;
      return result;
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '获取学习步骤失败', showToast: false);
      final result = Result<List<UserStudyStepVo>>("ERROR", "获取学习步骤失败: $e", false);
      result.data = null;
      return result;
    }
  }

  Future<Result<List<UserStudyStepVo>>> getActiveUserStudySteps() async {
    try {
      final steps = await _studyStepsService.getActiveUserStudySteps();
      final result = Result<List<UserStudyStepVo>>("SUCCESS", "获取成功", true);
      result.data = steps;
      return result;
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '获取激活的学习步骤失败', showToast: false);
      final result = Result<List<UserStudyStepVo>>("ERROR", "获取激活的学习步骤失败: $e", false);
      result.data = null;
      return result;
    }
  }

  Future<Result<void>> saveUserStudySteps(List<UserStudyStepVo> steps) async {
    try {
      await _studyStepsService.saveUserStudySteps(steps);
      try {
        ThrottledDbSyncService().requestSync();
      } catch (syncError, stackTrace) {
        ErrorHandler.handleError(syncError, stackTrace, logPrefix: '同步学习步骤到服务器失败', showToast: false);
      }
      return Result("SUCCESS", "保存成功", true);
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '保存学习步骤失败', showToast: false);
      return Result("ERROR", "保存学习步骤失败: $e", false);
    }
  }

  Future<List<LearningWordVo>> getCurrentBatchCache() async {
    final sw = Stopwatch()..start();
    try {
      final user = Global.getLoggedInUser();
      if (user == null) {
        Global.logger.e('获取批次单词失败：用户未登录');
        return [];
      }

      Global.logger.d('开始获取批次单词: userId=${user.id}');
      final db = MyDatabase.instance;
      final now = AppClock.now();

      // 查询今日已分配批次的单词 (batchId > 0 表示该词属于今日学习计划)
      final query = db.select(db.learningWords)
        ..where((tbl) => tbl.userId.equals(user.id) & tbl.batchId.isBiggerThanValue(0))
        ..orderBy([
          (tbl) => OrderingTerm(expression: tbl.batchId),
          (tbl) => OrderingTerm(expression: tbl.learningOrder),
        ]);
      final todayWords = await query.get();

      // 获取学习环节总数 (modeCount)
      final stepsVo = await _studyStepsService.getActiveUserStudySteps();
      final steps = stepsVo
          .map((vo) => UserStudyStep(
                userId: user.id,
                studyStep: vo.studyStep,
                seq: vo.seq,
                state: vo.state,
                createTime: now,
                updateTime: now,
              ))
          .toList();
      final modeCount = steps.length;

      // 获取用户已掌握的单词（状态驱动）
      final masteredWords = await db.masteredWordsDao.getMasteredWordsForUser(user.id);
      final masteredWordIds = masteredWords.map((e) => e.wordId).toSet();

      // 状态驱动：推导当前批次起始位置 (batchStartIndex)
      const int batchSize = 10;
      int batchStartIndex = _calculateBatchStartIndex(todayWords, modeCount, masteredWordIds, batchSize: batchSize);
      if (batchStartIndex == -1) {
        Global.logger.d('所有批次单词已完成');
        return [];
      }

      // 获取当前批次的单词（最多10个）
      List<LearningWord> batchWords = [];
      for (int i = batchStartIndex; i < todayWords.length && i < batchStartIndex + batchSize; i++) {
        batchWords.add(todayWords[i]);
      }

      Global.logger.d('获取到批次单词数量: ${batchWords.length}, 批次起始索引: $batchStartIndex');

      // 转换为 LearningWordVo
      final result = <LearningWordVo>[];
      if (batchWords.isEmpty) return result;

      // 1. 批量获取单词基本信息
      final wordIds = batchWords.map((bw) => bw.wordId).toList();
      final wordsList = await db.wordsDao.getWordsByIds(wordIds);
      final wordMap = {for (var w in wordsList) w.id: w};

      // 2. 批量获取释义项 (仅获取通用词典释义作为列表快速显示，或获取所有释义项后在内存过滤)
      // 注意：为了极致性能，在列表页我们可能不需要 getWordMeaningItems 那么复杂的过滤逻辑
      // 这里采用类似 getLearningWordsForAPage 的批量获取方式
      final meaningItemsQuery = db.select(db.meaningItems)..where((mi) => mi.wordId.isIn(wordIds));
      final allMeaningItems = await meaningItemsQuery.get();
      final meaningItemsMap = <String, List<MeaningItem>>{};
      for (var mi in allMeaningItems) {
        meaningItemsMap.putIfAbsent(mi.wordId, () => []).add(mi);
      }

      final userVo = UserVo.fromUser(user);

      for (final batchWord in batchWords) {
        final word = wordMap[batchWord.wordId];
        if (word != null) {
          // 构建 WordVo 对象
          final wordVo = WordVo.c2(word.spell)
            ..id = word.id
            ..shortDesc = word.shortDesc
            ..longDesc = word.longDesc
            ..pronounce = word.pronounce
            ..americaPronounce = word.americaPronounce
            ..britishPronounce = word.britishPronounce
            ..popularity = word.popularity;

          // 获取并转换释义项
          final mItems = meaningItemsMap[word.id] ?? [];
          wordVo.meaningItems = mItems
              .map((mi) => MeaningItemVo(mi.id, mi.ciXing, mi.meaning, null, null, null))
              .toList();

          // 构建 LearningWordVo
          final learningWordVo = LearningWordVo(
              userVo,
              batchWord.addTime,
              batchWord.addDay,
              batchWord.lastLearningDate,
              batchWord.learningOrder,
              batchWord.learnedTimes,
              wordVo,
              batchWord.batchId,
              batchWord.stability,
              batchWord.difficulty,
              batchWord.elapsedDays,
              batchWord.scheduledDays,
              batchWord.reps,
              batchWord.lapses,
              batchWord.state);

          result.add(learningWordVo);
        } else {
          Global.logger.e('批次单词不存在: wordId=${batchWord.wordId}');
        }
      }

      if (result.isEmpty) {
        Global.logger.w('当前批次没有单词可供复习');
      }
      Global.logger.d('StudyBo: getCurrentBatchCache completed in ${sw.elapsedMilliseconds}ms (count=${result.length})');
      
      // 预生成 AI 短文
      if (result.isNotEmpty) {
        _triggerAiStoryPreGeneration(result.map((w) => w.word.spell).toList());
      }

      return result;
    } catch (e, stackTrace) {
      Global.logger.e('获取批次单词失败: $e', stackTrace: stackTrace);
      return [];
    }
  }

  // 游戏相关
  Future<Result<int>> throwDiceAndSave() async {
    try {
      Global.logger.d('开始掷骰子并保存结果');
      final db = MyDatabase.instance;

      // 获取当前登录用户
      final user = Global.getLoggedInUser();
      if (user == null) {
        Global.logger.e('掷骰子失败: 用户未登录');
        return Result("ERROR", "用户未登录", false);
      }

      // 检查用户是否有掷骰子机会
      if (user.throwDiceChance <= 0) {
        Global.logger.e('掷骰子失败: 没有掷骰子机会');
        return Result("ERROR", "没有掷骰子机会", false);
      }

      // 生成1-5的随机数
      final cowDung = Random().nextInt(5) + 1;
      Global.logger.d('掷骰子结果: $cowDung');

      // 直接使用掷骰子结果，不再翻倍
      final finalCowDung = cowDung;
      Global.logger.d('最终魔法泡泡数: $finalCowDung');

      // 更新用户的魔法泡泡数和掷骰子机会
      await db.usersDao.saveUser(
          user.copyWith(
            cowDung: user.cowDung + finalCowDung,
            throwDiceChance: user.throwDiceChance - 1,
          ),
          true);

      // 记录用户操作
      final now = AppClock.now();

      // 记录魔法泡泡奖励日志
      final log = UserCowDungLog(
        id: now.millisecondsSinceEpoch.toString(),
        userId: user.id,
        delta: finalCowDung,
        cowDung: user.cowDung + finalCowDung,
        theTime: now,
        reason: "throw dice after learning",
        createTime: now,
        updateTime: now,
      );
      await db.userCowDungLogsDao.insertEntity(log, true);
      await db.userOpersDao.saveUserOper(
          UserOper(
            id: now.millisecondsSinceEpoch.toString(),
            userId: user.id,
            operType: OperType.throwDice.value,
            operTime: now,
            createTime: now,
            updateTime: now,
          ),
          true);

      // 触发数据库同步
      ThrottledDbSyncService().requestSync();
      Global.logger.d('掷骰子结果已保存到本地并触发同步');

      return Result("SUCCESS", "保存成功", true)..data = finalCowDung;
    } catch (e, stackTrace) {
      Global.logger.e('掷骰子异常: $e');
      Global.logger.e('异常堆栈: $stackTrace');
      return Result("ERROR", "掷骰子失败: $e", false);
    }
  }

  // 打卡相关
  Future<Result<int>> saveDakaRecord(String content) async {
    try {
      Global.logger.d('开始保存打卡记录: content=$content');
      final db = MyDatabase.instance;

      // 获取当前登录用户
      final user = Global.getLoggedInUser();
      if (user == null) {
        Global.logger.e('保存打卡记录失败: 用户未登录');
        return Result("ERROR", "用户未登录", false);
      }

      // 获取当前时间
      final now = AppClock.now();
      final today = DateUtils.businessDate(now);

      // 检查今天是否已经打卡
      final existingDaka = await db.dakasDao.findById(user.id, today);
      if (existingDaka != null) {
        Global.logger.w('用户今天已经打卡，更新打卡内容');
        // 更新现有打卡记录
        await db.dakasDao.saveDaka(
            existingDaka.copyWith(
              textContent: Value(content),
              updateTime: now,
            ),
            true);
      } else {
        // 创建新的打卡记录
        final daka = Daka(
          userId: user.id,
          forLearningDate: today,
          textContent: content,
          createTime: now,
          updateTime: now,
        );
        await db.dakasDao.saveDaka(daka, true);

        // 更新用户打卡统计信息
        int newDakaDayCount = user.dakaDayCount + 1;
        int newContinuousDakaDayCount = 1;
        if (user.lastDakaDate != null) {
          final lastDate = DateUtils.businessDate(user.lastDakaDate!);
          final yesterday = today.subtract(const Duration(days: 1));
          if (lastDate.isAtSameMomentAs(yesterday)) {
            newContinuousDakaDayCount = user.continuousDakaDayCount + 1;
          } else if (lastDate.isAtSameMomentAs(today)) {
            // 虽然正常逻辑下 existingDaka != null 会拦截重复打卡，但在并发或异常流中，
            // 如果走到这里发现日期相同，则保持连续天数不变，总天数不增。
            newContinuousDakaDayCount = user.continuousDakaDayCount;
            newDakaDayCount = user.dakaDayCount;
          }
        }
        int newMaxContinuousDakaDayCount = max(user.maxContinuousDakaDayCount, newContinuousDakaDayCount);
        double newDakaRatio = user.learnedDays > 0 ? newDakaDayCount / user.learnedDays : 1.0;

        // 给用户一次掷骰子机会 (仅限每日首次打卡) 并更新统计信息
        await db.usersDao.saveUser(
            user.copyWith(
              throwDiceChance: user.throwDiceChance + 1,
              dakaDayCount: newDakaDayCount,
              continuousDakaDayCount: newContinuousDakaDayCount,
              maxContinuousDakaDayCount: newMaxContinuousDakaDayCount,
              lastDakaDate: Value(now),
              dakaRatio: Value(newDakaRatio),
            ),
            true);
      }

      // 记录打卡操作
      await db.userOpersDao.saveUserOper(
          UserOper(
            id: now.millisecondsSinceEpoch.toString(),
            userId: user.id,
            operType: OperType.daka.value,
            operTime: now,
            createTime: now,
            updateTime: now,
          ),
          true);

      // 动态推导并纠正打卡天数统计，防止多端数据冲突
      await UserBo().updateAndSyncUserDakaStats(user.id);

      // 触发数据库同步
      ThrottledDbSyncService().requestSync();
      Global.logger.d('打卡记录已保存到本地并触发同步');

      // 发送事件，通知首页打卡状态已变
      EventBus.publishTodayStudyPlanFinished(TodayStudyPlanFinishedEvent());

      return Result("SUCCESS", "保存成功", true)..data = 1;
    } catch (e, stackTrace) {
      Global.logger.e('保存打卡记录失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "保存打卡记录失败: ${e.toString()}", false);
    }
  }

  /// 完成当前批次列表学习
  Future<Result<void>> completeListStepForCurrentBatch() async {
    try {
      Global.logger.d('开始完成批次列表学习...');
      final db = MyDatabase.instance;
      // 获取当前 user
      final user = Global.getLoggedInUser();
      if (user == null) {
        return Result("ERROR", "用户未登录", false);
      }

      final now = AppClock.now();

      var todayWords = await StudyCacheManager().getTodayWords(db, user.id);

      if (todayWords.isEmpty) {
        return Result("ERROR", "今日没有学习单词", false);
      }

      // 获取当前 active steps count
      final stepsVo = await _studyStepsService.getActiveUserStudySteps();
      final steps = stepsVo
          .map((vo) => UserStudyStep(
                userId: user.id,
                studyStep: vo.studyStep,
                seq: vo.seq,
                state: vo.state,
                createTime: now,
                updateTime: now,
              ))
          .toList();
      final modeCount = steps.length;
      if (modeCount == 0) {
        return Result("ERROR", "未配置学习步骤", false);
      }

      // 计算掌握情况（状态驱动）
      final masteredWords = await db.masteredWordsDao.getMasteredWordsForUser(user.id);
      final masteredWordIds = masteredWords.map((e) => e.wordId).toSet();

      // 计算 batchStartIndex
      final batchStartIndex = _calculateBatchStartIndex(todayWords, modeCount, masteredWordIds);
      if (batchStartIndex == -1) {
        return Result("ERROR", "所有单词已完成列表学习", false);
      }

      // 获取当前 batch words
      final batchWords = <LearningWord>[];
      for (int i = batchStartIndex; i < todayWords.length && i < batchStartIndex + 10; i++) {
        batchWords.add(todayWords[i]);
      }

      if (batchWords.isEmpty) {
        return Result("ERROR", "当前没有批次单词需要完成列表学习", false);
      }

      bool anyUpdated = false;
      for (final word in batchWords) {
        int currentStepIndex = word.todayLearnedTimes;
        if (currentStepIndex < modeCount && steps[currentStepIndex].studyStep == 'List') {
          final updatedWord = word.copyWith(
            learnedTimes: word.learnedTimes + 1,
            todayLearnedTimes: word.todayLearnedTimes + 1,
            lastLearningDate: Value(AppClock.today()),
          );
          await StudyCacheManager().saveAndSyncWordState(db, updatedWord);
          anyUpdated = true;
        }
      }

      if (anyUpdated) {
        ThrottledDbSyncService().requestSync(immediate: true);
        return Result("SUCCESS", "完成列表学习成功", true);
      } else {
        return Result("SUCCESS", "无需更新", true);
      }
    } catch (e, stackTrace) {
      Global.logger.e('完成批次列表学习失败', error: e, stackTrace: stackTrace);
      return Result("ERROR", "完成列表学习失败: $e", false);
    }
  }

  /// 获取下一个学习单词
  ///
  /// [isWordMastered] 当前单词是否已掌握
  /// [gotoNext] 是否跳转到下一个单词/学习模式
  ///   - true: 会推进学习进度，移动到下一个单词或下一个学习模式，并更新用户的学习位置
  ///   - false: 仅刷新当前单词，不改变学习位置（用于初始加载、从批次列表返回后刷新等场景）
  /// [fsrsRating] 当前单词的学习评分（来自 FSRS 算法），用于计算未来的复习时间
  ///
  /// 返回下一个单词的学习信息，包括单词详情、学习模式、混淆项等
  Future<Result<GetWordResult>> getWord(bool isWordMastered, bool gotoNext, {FsrsRating? fsrsRating}) async {
    try {
      final swTotal = Stopwatch()..start();
      Global.logger.d('开始获取单词: isWordMastered=$isWordMastered, gotoNext=$gotoNext, fsrsRating=$fsrsRating');
      final db = MyDatabase.instance;

      final swUser = Stopwatch()..start();
      // 获取当前登录用户
      final user = Global.getLoggedInUser();
      if (user == null) {
        Global.logger.e('获取下一个单词失败: 用户未登录');
        return Result("ERROR", "用户未登录", false);
      }
      Global.logger.d('🐛 [BDC Performance Item] 获取用户状态耗时: ${swUser.elapsedMilliseconds} ms');

      // 跨天检测：比较当前业务日期与用户记录的最后学习业务日期
      final DateTime now = AppClock.now();
      final DateTime today = AppClock.today();
      Global.logger.i('getWord 跨天检测：user.lastLearningDate=${user.lastLearningDate}, today=$today, now=$now, equals=${user.lastLearningDate == today}');
      if (user.lastLearningDate != null && user.lastLearningDate != today) {
        Global.logger.w('检测到跨天：user.lastLearningDate=${user.lastLearningDate}, today=$today。触发 NEW_DAY 终止学习流程！');
        return Result<GetWordResult>("NEW_DAY", "已进入新的一天，今天的学习已终止", false);
      }

      final swSteps = Stopwatch()..start();
      // 获取用户的学习步骤配置
      final stepsVo = await _studyStepsService.getActiveUserStudySteps();
      final steps = stepsVo
          .map((vo) => UserStudyStep(
                userId: user.id,
                studyStep: vo.studyStep,
                seq: vo.seq,
                state: vo.state,
                createTime: now,
                updateTime: now,
              ))
          .toList();
      final activeStepCount = steps.length;
      if (activeStepCount == 0) {
        Global.logger.e('Error: No active study steps found for user ${user.id}. Cannot proceed.');
        return Result("ERROR", "用户学习步骤未配置", false);
      }
      Global.logger.d('🐛 [BDC Performance Item] 获取用户学习步骤耗时: ${swSteps.elapsedMilliseconds} ms');

      final swWords = Stopwatch()..start();
      var todayWords = await StudyCacheManager().getTodayWords(db, user.id);

      if (todayWords.isEmpty) {
        return _buildTodayStudyFinishedResult();
      }
      Global.logger.d('🐛 [BDC Performance Item] 查询今日单词列表耗时: ${swWords.elapsedMilliseconds} ms');

      final swMastered = Stopwatch()..start();
      final masteredWordIds = await StudyCacheManager().getMasteredWordIds(db, user.id);
      Global.logger.d('🐛 [BDC Performance Item] 查询已掌握单词ID耗时: ${swMastered.elapsedMilliseconds} ms');

      // 状态驱动：推导当前批次起始位置 (batchStartIndex)
      const int batchSize = 10;
      int batchStartIndex = _calculateBatchStartIndex(todayWords, activeStepCount, masteredWordIds, batchSize: batchSize);
      if (batchStartIndex == -1) {
        return _buildTodayStudyFinishedResult();
      }

      // 获取当前批次的 10 个词
      List<LearningWord> batchWords = [];
      for (int i = batchStartIndex; i < todayWords.length && i < batchStartIndex + batchSize; i++) {
        batchWords.add(todayWords[i]);
      }

      // 异步预生成 AI 短文
      unawaited(Future(() async {
        try {
          List<String> spells = [];
          for (var bw in batchWords) {
            final wordItem = await db.wordsDao.getWordById(bw.wordId);
            if (wordItem != null) spells.add(wordItem.spell);
          }
          _triggerAiStoryPreGeneration(spells);
        } catch (e) {
          Global.logger.w('预获取批次单词拼写失败: $e');
        }
      }));

      // 添加批次状态日志
      Global.logger.d('~~~~~BDC_BATCH: startIdx=$batchStartIndex, batchSize=${batchWords.length}, activeStepCount=$activeStepCount');
      for (var w in batchWords) {
        final bool isMastered = _isEffectivelyMastered(w, masteredWordIds);
        final bool isFinished = isMastered || w.todayLearnedTimes >= activeStepCount;
        Global.logger.d('  - [${w.wordId}] todayTimes=${w.todayLearnedTimes}, isMastered=$isMastered, isFinished=$isFinished');
      }

      // 在当前批次内，推导当前单词和环节
      List<LearningWord> sortedBatchWords = List.from(batchWords);
      sortedBatchWords.sort((a, b) {
        // 状态驱动：已掌握单词视为已完成今日所有环节
        final bool isAFinished = _isEffectivelyMastered(a, masteredWordIds);
        final bool isBFinished = _isEffectivelyMastered(b, masteredWordIds);

        final int effA = isAFinished ? activeStepCount : a.todayLearnedTimes;
        final int effB = isBFinished ? activeStepCount : b.todayLearnedTimes;

        // 优先练习今日学习次数较少的单词
        if (effA != effB) {
          return effA.compareTo(effB);
        }
        // 次数相同时，严格按照既定学习序号排序，确保“从左到右”的直观体验
        return a.learningOrder.compareTo(b.learningOrder);
      });

      final currentWordForPos = sortedBatchWords.first;
      int currentWordIndex = todayWords.indexOf(currentWordForPos);

      // 获取当前学习环节：由该单词今日已练习的次数推导
      // 状态驱动：已掌握单词直接视为处于最后一个环节或已越过
      final bool currentWordFinished = _isEffectivelyMastered(currentWordForPos, masteredWordIds);
      int currentStepIndex = currentWordFinished ? activeStepCount : currentWordForPos.todayLearnedTimes;
      if (currentStepIndex >= activeStepCount) {
        currentStepIndex = activeStepCount - 1;
      }

      // allStepsCompletedForWord 需要在后面的批次边界逻辑中也用到
      bool allStepsCompletedForWord = currentStepIndex >= steps.length - 1;

      // 仅在推进进度或提供评分时更新当前单词状态
      // fsrsRating != null 或 isWordMastered = true 时，说明用户已经完成了一次对该词的有效评价，需要保存
      bool shouldSave = gotoNext || fsrsRating != null || isWordMastered;
      if (shouldSave) {
        final currWord = todayWords[currentWordIndex];
        await updateCurrWord(
          isWordMastered: isWordMastered,
          currWord: currWord,
          user: user,
          now: now,
          db: db,
          allStepsCompletedForWord: allStepsCompletedForWord,
          fsrsRating: fsrsRating,
        );

        // 同步内存状态
        if (gotoNext) {
          if (isWordMastered) {
            masteredWordIds.add(currWord.wordId);
          }
        }
      }

      // 如果当前是列表模式，直接返回列表页面，不关心下一个单词逻辑（因为是由 "CompleteList" 触发批量进度）
      bool isListStep = currentStepIndex < steps.length && steps[currentStepIndex].studyStep == 'List';
      if (isListStep) {
        Global.logger.d('当前为列表模式，显示批次单词列表');
        return Result<GetWordResult>("SUCCESS", "获取成功", true)
          ..data = GetWordResult(
            null,
            currentStepIndex,
            null,
            [0, 0],
            null,
            false,
            false,
            null,
            null,
            null,
            null,
            [],
            [],
            [],
            false,
            false,
          );
      }

      // 完全基于当前（已更新的）状态，重新推导下一个单词
      int nextBatchStartIndex = _calculateBatchStartIndex(todayWords, activeStepCount, masteredWordIds, batchSize: batchSize);
      if (nextBatchStartIndex == -1) {
        return _buildTodayStudyFinishedResult();
      }

      // 获取下一个单词所在的批次
      List<LearningWord> nextBatchWords = [];
      for (int i = nextBatchStartIndex; i < todayWords.length && i < nextBatchStartIndex + batchSize; i++) {
        nextBatchWords.add(todayWords[i]);
      }

      // 按照学习效率 (eff) 排序，找出该批次最需要学习的下一个单词
      nextBatchWords.sort((a, b) {
        final bool isAFinished = _isEffectivelyMastered(a, masteredWordIds);
        final bool isBFinished = _isEffectivelyMastered(b, masteredWordIds);

        final int effA = isAFinished ? activeStepCount : a.todayLearnedTimes;
        final int effB = isBFinished ? activeStepCount : b.todayLearnedTimes;

        if (effA != effB) {
          return effA.compareTo(effB);
        }
        // 次数相同时，严格按照既定学习序号排序
        return a.learningOrder.compareTo(b.learningOrder);
      });

      final nextWordForPos = nextBatchWords.first;
      int nextWordIndex = todayWords.indexOf(nextWordForPos);

      // 计算下一个单词应该展示的学习环节
      final bool nextWordFinished = _isEffectivelyMastered(nextWordForPos, masteredWordIds);
      int nextStepIndex = nextWordFinished ? activeStepCount : nextWordForPos.todayLearnedTimes;
      if (nextStepIndex >= activeStepCount) {
        nextStepIndex = activeStepCount - 1;
      }

      // 获取目标学习单词，仅返回其ID，释义交由本地通过 WordBo.getWordMeaningItems 加载
      final returnWord = todayWords[nextWordIndex];
      final userVo = UserVo.fromUser(user);
      final wordVo = WordVo.c2('')..id = returnWord.wordId; // 仅返回ID
      final learningWordVo = LearningWordVo(
          userVo,
          returnWord.addTime,
          returnWord.addDay,
          returnWord.lastLearningDate,
          returnWord.learningOrder,
          returnWord.learnedTimes,
          wordVo,
          returnWord.batchId,
          returnWord.stability,
          returnWord.difficulty,
          returnWord.elapsedDays,
          returnWord.scheduledDays,
          returnWord.reps,
          returnWord.lapses,
          returnWord.state);

      final swMeaningItems = Stopwatch()..start();
      // 使用 WordBo.getWordMeaningItems 获取目标单词释义并用于生成混淆项
      final targetMeaningItems = await WordBo().getWordMeaningItems(returnWord.wordId, returnWord.userId);
      final targetMeaningItemVos = targetMeaningItems.map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();
      Global.logger.d('🐛 [BDC Performance Item] 加载当前词释义项耗时: ${swMeaningItems.elapsedMilliseconds} ms');

      final swDistractor = Stopwatch()..start();
      // 生成两个混淆单词（其释义同样通过 WordBo.getWordMeaningItems 获取）
      final otherWords = await getTwoOtherWords(steps, nextStepIndex, targetMeaningItemVos, todayWords, returnWord, db);
      Global.logger.d('🐛 [BDC Performance Item] 加载混淆项耗时: ${swDistractor.elapsedMilliseconds} ms');

      // 计算学习进度
      // 状态驱动：根据今日单词的实际学习次数计算进度
      // 每个单词的每个学习步骤都算作一个进度单位
      final totalWordsToday = todayWords.length;

      // 计算所有单词的今日已学习次数总和
      int totalCompletedSteps = 0;
      for (final word in todayWords) {
        // 状态驱动：已掌握单词贡献满分进度，活跃单词取 min(已学次数, 总环节数) 避免溢出
        if (_isEffectivelyMastered(word, masteredWordIds)) {
          totalCompletedSteps += activeStepCount;
        } else {
          totalCompletedSteps += min(word.todayLearnedTimes, activeStepCount);
        }
      }

      // 总步数 = 单词数 × 每个单词的步骤数
      final totalSteps = totalWordsToday * activeStepCount;

      final progress = [totalCompletedSteps, totalSteps];

      final result = Result<GetWordResult>("SUCCESS", "获取成功", true)
        ..data = GetWordResult(
          learningWordVo,
          nextStepIndex,
          otherWords,
          progress,
          null, // sound
          false, // finished
          false, // noWord
          [], // cigens
          [], // additionalInfos
          [], // errorReports
          null, // shortDesc
          [], // images
          [], // verbTenses
          [], // shortDescChineses
          false, // inRawWordDict
          _isEffectivelyMastered(returnWord, masteredWordIds), // wordMastered
        );

      Global.logger.d('🐛 [BDC Performance Item] getWord 内部计算总耗时: ${swTotal.elapsedMilliseconds} ms');
      return result;
    } catch (e, stackTrace) {
      Global.logger.e('获取下一个单词失败 [StudyBo]: $e', stackTrace: stackTrace);
      rethrow; // 直接抛出异常，不再包装成 Result，保留完整堆栈
    }
  }

  Future<void> updateCurrWord({
    required bool isWordMastered,
    required LearningWord currWord,
    required User user,
    required DateTime now,
    required MyDatabase db,
    required bool allStepsCompletedForWord,
    FsrsRating? fsrsRating,
  }) async {
    // 停止使用 dateOnlyNow，保留完整时间戳以支持状态驱动定位

    if (isWordMastered) {
      // 保存已掌握单词
      await _saveMasteredWord(
        learningWord: currWord,
        user: user,
        now: now,
        db: db,
      );
      return;
    }

    if (fsrsRating == FsrsRating.again) {
      // 若评分是 Again (答错), 则保存错词
      await saveWrongWord(currWord, db, user, now);
    }

    // FSRS 逻辑
    FSRSItem? nextFsrs;
    if (fsrsRating != null) {
      final fsrs = FSRS();
      if (currWord.stability == null || currWord.stability == 0.0) {
        if (currWord.stability == 0.0) {
           Global.logger.w('发现存量数据 stability 为 0.0, wordId: ${currWord.wordId}, 将视同新词执行 init');
        }
        // 第一次使用 FSRS
        nextFsrs = fsrs.init(fsrsRating);
      } else {
        // 复习
        final currentFsrs = FSRSItem(
          stability: currWord.stability!,
          difficulty: currWord.difficulty!,
          elapsedDays: currWord.elapsedDays!,
          scheduledDays: currWord.scheduledDays!,
          reps: currWord.reps!,
          lapses: currWord.lapses!,
          state: FsrsStateExt.fromInt(currWord.state),
        );
        // 计算经过的天数 (使用业务天数差)
        int elapsedDays = 0;
        if (currWord.lastLearningDate != null) {
          final lastDate = DateUtils.businessDate(currWord.lastLearningDate!);
          final todayDate = AppClock.today();
          elapsedDays = todayDate.difference(lastDate).inDays;
        }
        nextFsrs = fsrs.next(currentFsrs, fsrsRating, elapsedDays);
      }
    }

    if (nextFsrs != null) {
      Global.logger.d('~~~~~FSRS稳定性计算结果: wordId=${currWord.wordId}, rating=$fsrsRating, old_stability=${currWord.stability?.toStringAsFixed(2)}, new_stability=${nextFsrs.stability.toStringAsFixed(2)}, elapsedDays=${nextFsrs.elapsedDays}, scheduledDays=${nextFsrs.scheduledDays}');
    }

    // 判定是否毕业（进入已掌握单词表）
    bool shouldGraduate = isWordMastered || (nextFsrs != null && nextFsrs.stability >= Constants.graduationStability);

    if (shouldGraduate) {
      // 保存已掌握单词
      await _saveMasteredWord(
        learningWord: currWord,
        user: user,
        now: now,
        db: db,
      );
      return;
    }

    // 更新学习状态
    Global.logger.d('Word ${currWord.wordId}. Updating FSRS and learnedTimes.');

    // 保存学习记录
    if (fsrsRating != null && nextFsrs != null) {
      await db.learningLogsDao.saveEntity(
        LearningLog(
          id: Util.uuid(),
          userId: user.id,
          wordId: currWord.wordId,
          rating: fsrsRating.value,
          stability: nextFsrs.stability,
          difficulty: nextFsrs.difficulty,
          elapsedDays: nextFsrs.elapsedDays,
          scheduledDays: nextFsrs.scheduledDays,
          createTime: now,
          updateTime: now,
        ),
        true,
      );
      
      // 更新历史每日统计 (单词数)
      await db.userStudyDailyStatsDao.incrementReviewCount(user.id, now);
      // 更新每日状态为“已学习”
      await db.userStudyDailyStatsDao.updateDayStatus(user.id, now, UserDayStatus.studied);
    }

    final updatedWord = currWord.copyWith(
      lastLearningDate: Value(AppClock.today()),
      learnedTimes: (currWord.learnedTimes) + 1,
      todayLearnedTimes: (currWord.todayLearnedTimes) + 1, // 无论对错，进度都要加1
      stability: nextFsrs != null ? Value(nextFsrs.stability) : const Value.absent(),
      difficulty: nextFsrs != null ? Value(nextFsrs.difficulty) : const Value.absent(),
      elapsedDays: nextFsrs != null ? Value(nextFsrs.elapsedDays) : const Value.absent(),
      scheduledDays: nextFsrs != null ? Value(nextFsrs.scheduledDays) : const Value.absent(),
      reps: nextFsrs != null ? Value(nextFsrs.reps) : const Value.absent(),
      lapses: nextFsrs != null ? Value(nextFsrs.lapses) : const Value.absent(),
      state: nextFsrs != null ? Value(nextFsrs.state.value) : const Value.absent(),
    );
    await _saveAndSyncWordState(updatedWord: updatedWord, db: db);

    // 触发同步到后端
    ThrottledDbSyncService().requestSync();
  }

  Future<void> saveHistoryFSRSUpdate({
    required LearningWordVo currWord,
    required FSRSItem nextFsrs,
    required FsrsRating newRating,
  }) async {
    final db = MyDatabase.instance;
    final user = Global.getLoggedInUser();
    if (user == null) return;
    final now = AppClock.now();

    final lwQuery = db.select(db.learningWords)
      ..where((tbl) => tbl.wordId.equals(currWord.word.id!) & tbl.userId.equals(user.id));
    final lwList = await lwQuery.get();
    if (lwList.isEmpty) return;
    final dbLw = lwList.first;

    // 1. 如果新评分为 Again，记入错词本
    if (newRating == FsrsRating.again) {
      await saveWrongWord(dbLw, db, user, now);
    }

    // 2. 覆盖替换最近的一条学习日志
    try {
      final logQuery = db.select(db.learningLogs)
        ..where((tbl) => tbl.wordId.equals(currWord.word.id!) & tbl.userId.equals(user.id))
        ..orderBy([(tbl) => OrderingTerm(expression: tbl.createTime, mode: OrderingMode.desc)])
        ..limit(1);
      final lastLogList = await logQuery.get();
      if (lastLogList.isNotEmpty) {
        final lastLog = lastLogList.first;
        await db.update(db.learningLogs).replace(lastLog.copyWith(
          rating: newRating.value,
          stability: nextFsrs.stability,
          difficulty: nextFsrs.difficulty,
          elapsedDays: nextFsrs.elapsedDays,
          scheduledDays: nextFsrs.scheduledDays,
          updateTime: now,
        ));
      }
    } catch (e, s) {
      Global.logger.e('历史模式下修改 FSRS，更新最近一条 LearningLog 失败', error: e, stackTrace: s);
    }

    // 3. 更新当前单词的 FSRS 字段，但不改动学习步骤次数
    final updatedWord = dbLw.copyWith(
      stability: Value(nextFsrs.stability),
      difficulty: Value(nextFsrs.difficulty),
      elapsedDays: Value(nextFsrs.elapsedDays),
      scheduledDays: Value(nextFsrs.scheduledDays),
      reps: Value(nextFsrs.reps),
      lapses: Value(nextFsrs.lapses),
      state: Value(nextFsrs.state.value),
    );
    await _saveAndSyncWordState(updatedWord: updatedWord, db: db);

    // 4. 触发数据同步
    ThrottledDbSyncService().requestSync();
  }

  Result<GetWordResult> _buildTodayStudyFinishedResult() {
    return Result("SUCCESS", "获取成功", true)
      ..data = GetWordResult(
        null,
        -1,
        null,
        [0, 0],
        null,
        true /* finished */,
        false,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        false,
        false,
      );
  }

  Future<void> _saveAndSyncWordState({
    required LearningWord updatedWord,
    required MyDatabase db,
  }) async {
    await StudyCacheManager().saveAndSyncWordState(db, updatedWord);
  }

  Future<void> saveWrongWord(
    LearningWord wrongWord,
    MyDatabase db,
    User user,
    DateTime now,
  ) async {
    // 将当前错误的单词添加到错词表
    Global.logger.d('添加错词到错词表: wordId=${wrongWord.wordId}');

    // 检查该单词是否已经在错词表中，避免重复添加
    final existingWrongWord = await db.userWrongWordsDao.getEntity(user.id, wrongWord.wordId);

    if (existingWrongWord == null) {
      // 将错词添加到错词表
      final userWrongWord = UserWrongWord(
        userId: user.id,
        wordId: wrongWord.wordId,
        createTime: now,
        updateTime: now,
      );
      await db.userWrongWordsDao.saveEntity(userWrongWord, true);
      Global.logger.d('错词添加到错词表成功: ${wrongWord.wordId}');
    } else {
      // 更新错词的时间，表示再次答错
      await db.userWrongWordsDao.saveEntity(
          existingWrongWord.copyWith(
            createTime: now, // 纯 DateTime?
            updateTime: now,
          ),
          true);
      Global.logger.d('错词已存在，更新时间: ${wrongWord.wordId}');
    }

    // 观察者模式：发射具象的“产生了新错词”事件
    Global.logger.d('[EventBus Debug] 准备发射 NewWrongWordEvent, wordId=${wrongWord.wordId}');
    EventBus.publishNewWrongWord(NewWrongWordEvent(wordId: wrongWord.wordId));
    Global.logger.d('[EventBus Debug] 已发射 NewWrongWordEvent');

    // 触发同步到后端
    ThrottledDbSyncService().requestSync();
  }

  Future<List<WordVo>> getTwoOtherWords(List<UserStudyStep> steps, int learningMode, List<MeaningItemVo> meaningItemVos,
      List<LearningWord> todayWords, LearningWord targetWordLearningData, MyDatabase db) async {
    final config = StudyConfig.fromCurrentUser();
    final strategy = DistractorStrategyFactory.getStrategy(config.distractorStrategy);
    return await strategy.getTwoOtherWords(
      steps: steps,
      learningMode: learningMode,
      meaningItemVos: meaningItemVos,
      todayWords: todayWords,
      targetWordLearningData: targetWordLearningData,
      db: db,
    );
  }

  /// 提供给UI：根据 wordId 和 userId 获取释义项（封装内部的 popularity limit 逻辑）
  Future<List<MeaningItemVo>> getMeaningItemsForWord(String wordId, String userId) async {
    final items = await WordBo().getWordMeaningItems(wordId, userId);
    return items.map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();
  }

  /// 状态驱动：推导当前批次起始位置 (batchStartIndex)
  /// 逻辑：找到第一个今日尚未完成所有学习环节的批次
  static int _calculateBatchStartIndex(List<LearningWord> todayWords, int modeCount, Set<String> masteredWordIds, {int batchSize = 10}) {
    for (int i = 0; i < todayWords.length; i += batchSize) {
      bool batchFinished = true;
      for (int j = i; j < i + batchSize && j < todayWords.length; j++) {
        // 状态驱动：如果单词已学完（达到毕业稳定性，或者在 masteredWords 表中存在，或者今日学习次数已达到模式环节总数）
        bool wordFinished = _isEffectivelyMastered(todayWords[j], masteredWordIds) || todayWords[j].todayLearnedTimes >= modeCount;
        if (!wordFinished) {
          batchFinished = false;
          break;
        }
      }
      if (!batchFinished) {
        return i;
      }
    }
    return -1; // 所有批次都学完了
  }

  /// 计算指定单词的指定学习模式, 在第几个顺位出现
  int calculateLearningIndexByWordIndexAndMode(int wordIndex, int mode, int modeCount, int todayWordCount, int batchWordCount) {
    // 新的学习顺序：
    // 1. 先完成当前批次所有单词的当前模式
    // 2. 再进入下一个模式
    // 3. 最后进入下一个批次
    final int batch = wordIndex ~/ batchWordCount;
    final int batchWordIndex = wordIndex % batchWordCount;

    // 计算当前批次的基础索引
    final batchBaseIndex = batch * batchWordCount * modeCount;
    // 计算当前单词在当前批次内的索引
    final batchWordBaseIndex = batchWordIndex + (mode * batchWordCount);

    return batchBaseIndex + batchWordBaseIndex;
  }

  /// 将单词标记为已掌握
  static bool _isEffectivelyMastered(LearningWord lw, Set<String> masteredWordIds) {
    if (masteredWordIds.contains(lw.wordId)) return true;
    if (lw.stability != null && lw.stability! >= Constants.graduationStability) return true;
    return false;
  }

  Future<void> _saveMasteredWord({
    required LearningWord learningWord,
    required User user,
    required DateTime now,
    required MyDatabase db,
  }) async {
    // 获取当前学习模式的总步骤数（用于饱和填充状态）
    final stepsVo = await _studyStepsService.getActiveUserStudySteps();
    final steps = stepsVo
        .map((vo) => UserStudyStep(
              userId: user.id,
              studyStep: vo.studyStep,
              seq: vo.seq,
              state: vo.state,
              createTime: now,
              updateTime: now,
            ))
        .toList();
    final int stepCount = steps.length;

    if (user.todayStudyStarted) {
      // 已经进入学习执行阶段：不删除记录，而是将状态“填满”
      // 这样进度条的分母保持不变，分子增加，体验更平滑
      final updatedWord = learningWord.copyWith(
        stability: Value(Constants.graduationStability),
        lastLearningDate: Value(AppClock.today()),
        learnedTimes: learningWord.learnedTimes + 1,
        todayLearnedTimes: stepCount, // 饱和今天的所有环节
      );
      await StudyCacheManager().saveAndSyncWordState(db, updatedWord);
    } else {
      // 还在规划阶段：直接删除该学习记录
      await StudyCacheManager().deleteAndSyncWordState(db, learningWord);
    }

    // 将单词添加到已掌握词书
    await StudyCacheManager().saveMasteredWordAndSync(db, user.id, learningWord.wordId);

    ThrottledDbSyncService().requestSync();
  }
}
