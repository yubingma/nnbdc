import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
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
import 'package:nnbdc/util/app_clock.dart';

/// 业务对象（BO）：承载本地实现逻辑
class StudyBo {
  final StudyStepsService _studyStepsService = StudyStepsService();
  static final StudyBo _instance = StudyBo._internal();

  factory StudyBo() {
    return _instance;
  }

  StudyBo._internal();

  Future<Result<List<int>>> prepareForStudy(bool addNewWordsIfNotEnough) async {
    try {
      Global.logger.d('开始准备学习单词...');
      final result = await LearningService.prepareTodayStudy(addNewWordsIfNotEnough);
      if (!result.success) {
        return result;
      }

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
      final result = Result<List<UserStudyStepVo>>("ERROR", "获取学习步骤失败，请稍后重试", false);
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
      final result = Result<List<UserStudyStepVo>>("ERROR", "获取激活的学习步骤失败，请稍后重试", false);
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
      return Result("ERROR", "保存学习步骤失败，请稍后重试", false);
    }
  }

  Future<List<LearningWordVo>> getCurrentStageCache() async {
    try {
      final user = Global.getLoggedInUser();
      if (user == null) {
        Global.logger.e('获取阶段单词失败：用户未登录');
        return [];
      }

      Global.logger.d('开始获取阶段单词: userId=${user.id}');
      final db = MyDatabase.instance;

      // 获取今天的开始和结束时间
      final DateTime now = AppClock.now();
      final DateTime dateOnlyNow = DateTime(now.year, now.month, now.day);
      final startOfDay = dateOnlyNow;
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

      // 查询今日学习单词，按学习顺序排序
      final query = db.select(db.learningWords)
        ..where((tbl) =>
            tbl.userId.equals(user.id) & tbl.lastLearningDate.isBiggerOrEqualValue(startOfDay) & tbl.lastLearningDate.isSmallerOrEqualValue(endOfDay))
        ..orderBy([(tbl) => OrderingTerm(expression: tbl.learningOrder)]);
      final todayWords = await query.get();

      // 获取当前学习位置
      int currentWordIndex = user.lastLearningPosition ?? 0;
      if (currentWordIndex < 0) currentWordIndex = 0;

      // 计算当前阶段的起始位置（每10个单词为一个阶段）
      int stageStartIndex = (currentWordIndex ~/ 10) * 10;

      // 获取当前阶段的单词（最多10个）
      List<LearningWord> stageWords = [];
      for (int i = stageStartIndex; i < todayWords.length && i < stageStartIndex + 10; i++) {
        stageWords.add(todayWords[i]);
      }

      Global.logger.d('获取到阶段单词数量: ${stageWords.length}, 阶段起始索引: $stageStartIndex');

      // 转换为 LearningWordVo
      final result = <LearningWordVo>[];
      for (final stageWord in stageWords) {
        final word = await db.wordsDao.getWordById(stageWord.wordId);
        if (word != null) {
          // 创建一个简单的UserVo对象
          final userVo = UserVo.c2(user.id);
          userVo.level = LevelVo(user.levelId);

          // 构建 WordVo 对象
          final wordVo = WordVo.c2(word.spell);
          wordVo.id = word.id;
          wordVo.shortDesc = word.shortDesc;
          wordVo.longDesc = word.longDesc;
          wordVo.pronounce = word.pronounce;
          wordVo.americaPronounce = word.americaPronounce;
          wordVo.britishPronounce = word.britishPronounce;
          wordVo.popularity = word.popularity;

          // 获取单词的释义项
          // 首先获取用户选择的词书列表
          final learningDictsQuery = db.select(db.learningDicts)..where((tbl) => tbl.userId.equals(user.id));
          final learningDicts = await learningDictsQuery.get();
          final selectedDictIds = learningDicts.map((d) => d.dictId).toList();

          // 优先从用户选择的词书中查询释义项
          final meaningItemQuery = db.select(db.meaningItems)
            ..where((mi) => mi.wordId.equals(word.id) & mi.dictId.isIn(selectedDictIds))
            ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);

          final meaningItems = await meaningItemQuery.get();

          // 如果单词在用户选择的词书中没有释义项，则从通用词典中查找
          if (meaningItems.isEmpty) {
            // 从通用词典中查询释义项
            final wordsWithoutMeaning = [word.id];
            final commonDictQuery = db.select(db.meaningItems)
              ..where((mi) => mi.wordId.isIn(wordsWithoutMeaning) & mi.dictId.equals(Global.commonDictId))
              ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);

            final commonMeaningItems = await commonDictQuery.get();
            meaningItems.addAll(commonMeaningItems);
          }

          List<MeaningItemVo> meaningItemVos = [];
          for (final mi in meaningItems) {
            final meaningItemVo = MeaningItemVo(
                mi.id,
                mi.ciXing,
                mi.meaning,
                null, // dict
                null, // synonyms
                null // sentences
                );
            meaningItemVos.add(meaningItemVo);
          }
          wordVo.meaningItems = meaningItemVos;

          // 构建 LearningWordVo
          final learningWordVo = LearningWordVo(userVo, stageWord.addTime, stageWord.addDay, stageWord.lifeValue, stageWord.lastLearningDate,
              stageWord.learningOrder, stageWord.learnedTimes, wordVo);

          result.add(learningWordVo);
        } else {
          Global.logger.e('阶段单词不存在: wordId=${stageWord.wordId}');
        }
      }

      if (result.isEmpty) {
        Global.logger.w('当前阶段没有单词可供复习');
      }
      return result;
    } catch (e, stackTrace) {
      Global.logger.e('获取阶段单词失败: $e', stackTrace: stackTrace);
      return [];
    }
  }

  // 游戏相关
  Future<Result<int>> throwDiceAndSave() async {
    try {
      Global.logger.d('开始掷骰子并保存结果');
      final db = MyDatabase.instance;

      // 获取当前登录用户
      final user = await db.usersDao.getLastLoggedInUser();
      if (user == null) {
        Global.logger.e('掷骰子失败: 用户未登录');
        return Result("ERROR", "用户未登录", false);
      }

      // 检查用户是否有掷骰子机会
      if (user.throwDiceChance <= 0) {
        Global.logger.e('掷骰子失败: 没有掷骰子机会');
        return Result("ERROR", "没有掷骰子机会", false);
      }

      // 生成1-20的随机数
      final cowDung = Random().nextInt(20) + 1;
      Global.logger.d('掷骰子结果: $cowDung');

      // 如果掷到20，翻倍
      final finalCowDung = cowDung == 20 ? cowDung * 2 : cowDung;
      Global.logger.d('最终泡泡糖数: $finalCowDung');

      // 更新用户的泡泡糖数和掷骰子机会
      await db.usersDao.saveUser(
          user.copyWith(
            cowDung: user.cowDung + finalCowDung,
            throwDiceChance: user.throwDiceChance - 1,
          ),
          true);

      // 记录泡泡糖奖励日志
      final log = UserCowDungLog(
        id: AppClock.now().millisecondsSinceEpoch.toString(),
        userId: user.id,
        delta: finalCowDung,
        cowDung: user.cowDung + finalCowDung,
        theTime: AppClock.now(),
        reason: "throw dice after learning",
      );
      await db.userCowDungLogsDao.insertEntity(log, true);

      // 记录用户操作
      await db.userOpersDao.saveUserOper(
          UserOper(
            id: AppClock.now().millisecondsSinceEpoch.toString(),
            userId: user.id,
            operType: OperType.throwDice.value,
            operTime: AppClock.now(),
            createTime: AppClock.now(),
            updateTime: AppClock.now(),
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
      final user = await db.usersDao.getLastLoggedInUser();
      if (user == null) {
        Global.logger.e('保存打卡记录失败: 用户未登录');
        return Result("ERROR", "用户未登录", false);
      }

      // 获取当前时间
      final now = AppClock.now();
      final today = DateTime(now.year, now.month, now.day);

      // 检查今天是否已经打卡
      final existingDaka = await db.dakasDao.findById(user.id, today);
      if (existingDaka != null) {
        Global.logger.w('用户今天已经打卡，更新打卡内容');
        // 更新现有打卡记录
        await db.dakasDao.saveDaka(
            existingDaka.copyWith(
              textContent: Value(content),
              updateTime: Value(now),
            ),
            true);
      } else {
        Global.logger.d('创建新的打卡记录');
        // 创建新的打卡记录
        final daka = Daka(
          userId: user.id,
          forLearningDate: today,
          textContent: content,
          createTime: now,
          updateTime: now,
        );
        await db.dakasDao.saveDaka(daka, true);
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

      // 给用户一次掷骰子机会
      await db.usersDao.saveUser(
          user.copyWith(
            throwDiceChance: user.throwDiceChance + 1,
          ),
          true);

      // 触发数据库同步
      ThrottledDbSyncService().requestSync();
      Global.logger.d('打卡记录已保存到本地并触发同步');

      return Result("SUCCESS", "保存成功", true)..data = 1;
    } catch (e, stackTrace) {
      Global.logger.e('保存打卡记录失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "保存打卡记录失败: ${e.toString()}", false);
    }
  }

  Future<Result<GetWordResult>> getNextWord(bool isAnswerCorrect, bool isWordMastered, bool shouldEnterNextStage, bool gotoNext) async {
    try {
      Global.logger.d('开始获取下一个单词: isAnswerCorrect=$isAnswerCorrect, isWordMastered=$isWordMastered, shouldEnterNextStage=$shouldEnterNextStage');
      final db = MyDatabase.instance;

      // 获取当前登录用户
      final user = await db.usersDao.getLastLoggedInUser();
      if (user == null) {
        Global.logger.e('获取下一个单词失败: 用户未登录');
        return Result("ERROR", "用户未登录", false);
      }

      // 跨天检测：直接根据用户 lastLearningDate 判断
      final DateTime now = AppClock.now();
      if (user.lastLearningDate != null) {
        final DateTime u = user.lastLearningDate!;
        final bool isSameDay = now.year == u.year && now.month == u.month && now.day == u.day;
        if (!isSameDay) {
          Global.logger.d('检测到跨天：user.lastLearningDate=$u, now=$now');
          return Result<GetWordResult>("NEW_DAY", "已进入新的一天，今天的学习已终止", true);
        }
      }
      final DateTime dateOnlyNow = DateTime(now.year, now.month, now.day);
      final startOfDay = dateOnlyNow; // Already date-only
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

      // 获取用户的学习步骤配置
      final steps = await db.userStudyStepsDao.getActiveUserStudySteps(user.id);
      final modeCount = steps.length;
      if (modeCount == 0) {
        Global.logger.e('Error: No active study steps found for user ${user.id}. Cannot proceed.');
        return Result("ERROR", "用户学习步骤未配置", false);
      }

      // 查询今日学习单词，按学习顺序排序
      final query = db.select(db.learningWords)
        ..where((tbl) =>
            tbl.userId.equals(user.id) & tbl.lastLearningDate.isBiggerOrEqualValue(startOfDay) & tbl.lastLearningDate.isSmallerOrEqualValue(endOfDay))
        ..orderBy([(tbl) => OrderingTerm(expression: tbl.learningOrder)]);
      var todayWords = await query.get();

      if (todayWords.isEmpty) {
        throw Exception('未知错误: 今日学习单词数为0');
      }

      // 获取当前单词索引 (currentWordIndex) 和 当前学习模式 (currentLearningMode)
      int currentWordIndex = user.lastLearningPosition ?? -1;
      if (currentWordIndex < 0 || currentWordIndex >= todayWords.length) {
        currentWordIndex = 0;
      }

      // 获取当前学习模式
      int currentLearningMode = user.lastLearningMode ?? -1;
      if (currentLearningMode < 0 || currentLearningMode >= modeCount) {
        currentLearningMode = 0;
      }

      // 更新当前单词的状态
      final currWord = todayWords[currentWordIndex];
      bool allStepsCompletedForWord = currentLearningMode >= steps.length - 1;
      await updateCurrWord(isWordMastered, currWord, user, now, db, isAnswerCorrect, allStepsCompletedForWord);

      // 移除了基于UserStageWord缓存的阶段复习逻辑，改为基于单词数量的简单判断

      // 计算下一个单词的索引 (nextWordIndex) 和学习模式 (nextLearningMode)
      int nextWordIndex = currentWordIndex;
      int nextLearningMode = currentLearningMode;
      if (shouldEnterNextStage) {
        nextWordIndex = currentWordIndex + 1;
        nextLearningMode = 0;
      } else if (gotoNext) {
        int stageWordCount = 10;
        bool isStageBounderyReached = (currentWordIndex + 1) % stageWordCount == 0;
        if (isStageBounderyReached) {
          if (allStepsCompletedForWord) {
            Global.logger.d('每学完10个单词，进入阶段复习模式: nextWordIndex=$nextWordIndex');
            return Result<GetWordResult>("SUCCESS", "获取成功", true)
              ..data = GetWordResult(
                null, -1, null, [0, 0], null, false, false, null, null, null,
                null,
                true, // shouldEnterReviewMode
                null, null, null, false,
                false, // wordMastered
              );
          } else {
            nextWordIndex = currentWordIndex - stageWordCount + 1;
            nextLearningMode = currentLearningMode == modeCount - 1 ? 0 : currentLearningMode + 1;
          }
        } else {
          nextWordIndex = currentWordIndex + 1;
          nextLearningMode = currentLearningMode;
        }
      }

      // 更新用户取词位置信息
      Global.logger
          .d("~~~~~~~~~~~~~~~~~~~~nextWordIndex: $nextWordIndex, nextLearningMode: $nextLearningMode, todayWords.length: ${todayWords.length}");
      if (nextWordIndex >= todayWords.length) {
        // 今日所有单词都学习完了
        return _buildTodayStudyFinishedResult();
      } else {
        // 更新用户取词位置信息
        await db.usersDao.saveUser(
            user.copyWith(
              lastLearningMode: Value(nextLearningMode),
              lastLearningPosition: Value(nextWordIndex),
            ),
            true);
      }

      // 获取目标学习单词, 并构建完整的GetWordResult
      final returnWord = todayWords[nextWordIndex];
      var result = await _buildGetWordResult(
        user: user,
        targetWordLearningData: returnWord,
        nextLearningMode: nextLearningMode,
        nextWordIndex: nextWordIndex,
        steps: steps,
        todayWords: todayWords,
        modeCount: modeCount,
        db: db,
      );
      return result;
    } catch (e, stackTrace) {
      Global.logger.e('获取下一个单词失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "获取下一个单词失败: ${e.toString()}", false);
    }
  }

  Future<void> updateCurrWord(
      bool isWordMastered, LearningWord currWord, User user, DateTime now, MyDatabase db, bool isAnswerCorrect, bool allStepsCompletedForWord) async {
    final DateTime dateOnlyNow = DateTime(now.year, now.month, now.day);
    if (isWordMastered) {
      // 保存已掌握单词
      await _saveMasteredWord(
        learningWord: currWord,
        user: user,
        now: now,
        dateOnlyNow: dateOnlyNow,
        db: db,
      );
    } else if (!isAnswerCorrect) {
      // 若回答错误, 则保存错词
      await saveWrongWord(currWord, db, user, now);
    } else if (allStepsCompletedForWord && isAnswerCorrect && currWord.lifeValue > 0) {
      Global.logger.d('All steps completed correctly for ${currWord.wordId}. Decrementing lifeValue.');
      await db.learningWordsDao.saveEntity(
          currWord.copyWith(
            lifeValue: (currWord.lifeValue) - 1, // 生命值减1
            lastLearningDate: Value(dateOnlyNow),
            learnedTimes: (currWord.learnedTimes) + 1,
          ),
          true);

      // 如果生命值降为0，则标记为已掌握
      if (currWord.lifeValue - 1 == 0) {
        await _saveMasteredWord(
          learningWord: currWord.copyWith(lifeValue: 0),
          user: user,
          now: now,
          dateOnlyNow: dateOnlyNow,
          db: db,
          updateUserMasteredCount: true,
        );
      }
    } else {
      // 如果不是上述情况 (回答错误/单词标记为已掌握/已完成今日学习)，
      // 只更新学习时间和学习次数，不改变生命值
      Global.logger
          .d('Word ${currWord.wordId}. All steps completed: $allStepsCompletedForWord, AnswerCorrect: $isAnswerCorrect. Updating learnedTimes only.');
      await db.learningWordsDao.saveEntity(
          currWord.copyWith(
            // lifeValue 不变
            lastLearningDate: Value(dateOnlyNow),
            learnedTimes: (currWord.learnedTimes) + 1,
          ),
          true);
    }
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
        false,
        null,
        null,
        null,
        false,
        false, // wordMastered
      );
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
            updateTime: Value(now),
          ),
          true);
      Global.logger.d('错词已存在，更新时间: ${wrongWord.wordId}');
    }
  }

  /// 获取单词的释义项，优先使用学习中词书的释义项
  Future<List<MeaningItem>> _getWordMeaningItems(String wordId, String userId, MyDatabase db) async {
    // 首先获取用户选择的词书列表
    final learningDictsQuery = db.select(db.learningDicts)..where((tbl) => tbl.userId.equals(userId));
    final learningDicts = await learningDictsQuery.get();
    final selectedDictIds = learningDicts.map((d) => d.dictId).toList();

    // 优先从用户选择的词书中查询释义项
    final meaningItemQuery = db.select(db.meaningItems)
      ..where((mi) => mi.wordId.equals(wordId) & mi.dictId.isIn(selectedDictIds))
      ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
    final meaningItems = await meaningItemQuery.get();

    // 如果单词在用户选择的词书中没有释义项，则从通用词典中查找
    if (meaningItems.isEmpty) {
      // 从通用词典中查询释义项
      final commonDictQuery = db.select(db.meaningItems)
        ..where((mi) => mi.wordId.equals(wordId) & mi.dictId.equals(Global.commonDictId))
        ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
      final commonMeaningItems = await commonDictQuery.get();
      
      // 应用popularityLimit过滤
      if (commonMeaningItems.isNotEmpty) {
        // 查询用户选择的词书的popularityLimit配置
        Map<String, int?> dictPopularityLimits = {};
        for (final learningDict in learningDicts) {
          final dict = await db.dictsDao.findById(learningDict.dictId);
          if (dict != null) {
            dictPopularityLimits[dict.id] = dict.popularityLimit;
          }
        }
        
        // 过滤通用释义
        final filteredCommonMeanings = <MeaningItem>[];
        for (final meaning in commonMeaningItems) {
          bool shouldInclude = true;
          
          // 如果有词书配置了popularityLimit，需要检查
          if (dictPopularityLimits.isNotEmpty) {
            final anyLimit = dictPopularityLimits.values.where((limit) => limit != null).isNotEmpty;
            if (anyLimit) {
              final int popularity = meaning.popularity;
              
              // 检查是否所有词书的popularityLimit都允许该释义
              shouldInclude = false;
              for (final limit in dictPopularityLimits.values) {
                if (limit == null) {
                  shouldInclude = true;
                  break;
                } else if (popularity <= limit) {
                  shouldInclude = true;
                  break;
                }
              }
            }
          }
          
          if (shouldInclude) {
            filteredCommonMeanings.add(meaning);
          }
        }
        
        meaningItems.addAll(filteredCommonMeanings);
      }
    }

    return meaningItems;
  }

  Future<List<WordVo>> getTwoOtherWords(List<UserStudyStep> steps, int learningMode, List<MeaningItemVo> meaningItemVos,
      List<LearningWord> todayWords, LearningWord targetWordLearningData, MyDatabase db) async {
    try {
      List<WordVo> otherWords = [];
      if ([StudyStep.word.json, StudyStep.meaning.json].contains(steps[learningMode].studyStep)) {
        String? targetCiXing;
        if (meaningItemVos.isNotEmpty && meaningItemVos.first.ciXing != null) {
          targetCiXing = meaningItemVos.first.ciXing!;
        } else {
          Global.logger.w('Target word has no meaningItems or first ciXing is null, cannot use targetCiXing for otherWords filtering.');
        }

        // 用于跟踪已选择的单词ID，避免重复
        final selectedWordIds = <String>{};

        // 1. 首先尝试从今日单词中获取混淆单词
        if (todayWords.isNotEmpty && todayWords.length > 1) {
          final random = Random();
          final startIndex = random.nextInt(todayWords.length);
          int currentLoopIndex = startIndex;
          int checkedCount = 0;
          int iterations = 0;

          while (otherWords.length < 2 && checkedCount < todayWords.length && iterations < todayWords.length * 2) {
            iterations++;
            final candidateLearningWord = todayWords[currentLoopIndex];
            currentLoopIndex = (currentLoopIndex + 1) % todayWords.length;
            checkedCount++;

            if (candidateLearningWord.wordId == targetWordLearningData.wordId || selectedWordIds.contains(candidateLearningWord.wordId)) {
              continue;
            }

            try {
              final candidateWordDetails = await db.wordsDao.getWordById(candidateLearningWord.wordId);
              assert(candidateWordDetails?.spell != null);

              // 检查词性匹配(仅判断第一个词性)
              bool ciXingMatch = false;

              // 获取候选单词的详细信息
              final wordDetails = await db.wordsDao.getWordById(candidateLearningWord.wordId);

              // 获取单词的释义项（优先使用学习中词书）
              final meaningItems = await _getWordMeaningItems(wordDetails!.id, targetWordLearningData.userId, db);

              for (final meaningItem in meaningItems) {
                if (meaningItem.ciXing == targetCiXing) {
                  ciXingMatch = true;
                  break;
                }
              }

              if (ciXingMatch) {
                final otherWordVo = WordVo.c2(wordDetails.spell);
                otherWordVo.id = wordDetails.id;
                otherWordVo.shortDesc = wordDetails.shortDesc;
                otherWordVo.longDesc = wordDetails.longDesc;
                otherWordVo.pronounce = wordDetails.pronounce;
                otherWordVo.americaPronounce = wordDetails.americaPronounce;
                otherWordVo.britishPronounce = wordDetails.britishPronounce;
                otherWordVo.popularity = wordDetails.popularity;
                otherWordVo.meaningItems = meaningItems.map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();
                otherWords.add(otherWordVo);
                selectedWordIds.add(candidateLearningWord.wordId);
              }
            } catch (e) {
              Global.logger.e('Error processing candidate word ${candidateLearningWord.wordId}: $e');
              continue;
            }
          }
        }

        // 2. 如果今日单词中找不到足够的混淆单词，从所有学习中单词(不包括今日单词)中查找词性相同的
        if (otherWords.length < 2) {
          // 计算今日的日期范围
          final DateTime now = AppClock.now();
          final DateTime startOfDay = DateTime(now.year, now.month, now.day);
          final DateTime endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

          // 获取用户的所有学习单词（不包括今日单词）
          final allLearningWordsQuery = db.select(db.learningWords)
            ..where((lw) =>
                lw.userId.equals(targetWordLearningData.userId) &
                (lw.lastLearningDate.isSmallerThanValue(startOfDay) | lw.lastLearningDate.isBiggerThanValue(endOfDay)));
          final allLearningWords = await allLearningWordsQuery.get();

          // 从所有学习单词中查找词性相同的混淆单词
          for (final learningWord in allLearningWords) {
            if (learningWord.wordId == targetWordLearningData.wordId || selectedWordIds.contains(learningWord.wordId)) {
              continue;
            }

            try {
              // 获取候选单词的详细信息
              final wordDetails = await db.wordsDao.getWordById(learningWord.wordId);
              if (wordDetails == null) continue;

              // 获取单词的释义项（优先使用学习中词书）
              final meaningItems = await _getWordMeaningItems(wordDetails.id, targetWordLearningData.userId, db);

              // 检查词性匹配
              bool ciXingMatch = false;
              for (final meaningItem in meaningItems) {
                if (meaningItem.ciXing == targetCiXing) {
                  ciXingMatch = true;
                  break;
                }
              }

              if (ciXingMatch) {
                final otherWordVo = WordVo.c2(wordDetails.spell);
                otherWordVo.id = wordDetails.id;
                otherWordVo.shortDesc = wordDetails.shortDesc;
                otherWordVo.longDesc = wordDetails.longDesc;
                otherWordVo.pronounce = wordDetails.pronounce;
                otherWordVo.americaPronounce = wordDetails.americaPronounce;
                otherWordVo.britishPronounce = wordDetails.britishPronounce;
                otherWordVo.popularity = wordDetails.popularity;
                otherWordVo.meaningItems = meaningItems.map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();
                otherWords.add(otherWordVo);
                selectedWordIds.add(learningWord.wordId);

                if (otherWords.length >= 2) break;
              }
            } catch (e) {
              Global.logger.e('Error processing learning word ${learningWord.wordId}: $e');
              continue;
            }
          }
        }

        // 3. 如果仍然找不到足够的混淆单词，从所有学习中单词随机选择以补足
        if (otherWords.length < 2) {
          // 重新获取所有学习单词（包括今日单词）用于随机选择
          final allLearningWordsForRandomQuery = db.select(db.learningWords)..where((lw) => lw.userId.equals(targetWordLearningData.userId));
          final allLearningWordsForRandom = await allLearningWordsForRandomQuery.get();

          // 随机打乱所有学习单词的顺序
          final shuffledLearningWords = List<LearningWord>.from(allLearningWordsForRandom);
          shuffledLearningWords.shuffle(Random());

          for (final learningWord in shuffledLearningWords) {
            if (learningWord.wordId == targetWordLearningData.wordId || selectedWordIds.contains(learningWord.wordId)) {
              continue;
            }

            try {
              final wordDetails = await db.wordsDao.getWordById(learningWord.wordId);
              if (wordDetails == null) continue;

              final otherWordVo = WordVo.c2(wordDetails.spell);
              otherWordVo.id = wordDetails.id;
              otherWordVo.shortDesc = wordDetails.shortDesc;
              otherWordVo.longDesc = wordDetails.longDesc;
              otherWordVo.pronounce = wordDetails.pronounce;
              otherWordVo.americaPronounce = wordDetails.americaPronounce;
              otherWordVo.britishPronounce = wordDetails.britishPronounce;
              otherWordVo.popularity = wordDetails.popularity;

              // 获取基本释义项（优先使用学习中词书）
              final meaningItems = await _getWordMeaningItems(wordDetails.id, targetWordLearningData.userId, db);
              otherWordVo.meaningItems = meaningItems.take(3).map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();

              otherWords.add(otherWordVo);
              selectedWordIds.add(learningWord.wordId);

              if (otherWords.length >= 2) break;
            } catch (e) {
              Global.logger.e('Error processing random learning word ${learningWord.wordId}: $e');
              continue;
            }
          }
        }

        Global.logger.d('Generated ${otherWords.length} otherWords for target ${targetWordLearningData.wordId}.');
      }
      return otherWords;
    } catch (e, stackTrace) {
      Global.logger.e('Error in getTwoOtherWords: $e', stackTrace: stackTrace);
      return []; // 发生错误时返回空列表，而不是让应用崩溃
    }
  }

  /// 计算指定单词的指定学习模式, 在第几个顺位出现
  int calculateLearningIndexByWordIndexAndMode(int wordIndex, int mode, int modeCount, int todayWordCount, int stageWordCount) {
    assert(wordIndex >= 0 && wordIndex < todayWordCount);
    assert(stageWordCount > 0);

    // 计算当前单词所在的学习阶段
    final stage = wordIndex ~/ stageWordCount;
    // 计算当前单词在阶段内的索引
    final stageWordIndex = wordIndex % stageWordCount;

    // 新的学习顺序：
    // 1. 先完成当前阶段所有单词的当前模式
    // 2. 再进入下一个模式
    // 3. 最后进入下一个阶段

    // 计算当前阶段的基础索引
    final stageBaseIndex = stage * stageWordCount * modeCount;
    // 计算当前单词在当前阶段内的索引
    final stageWordBaseIndex = stageWordIndex + (mode * stageWordCount);

    return stageBaseIndex + stageWordBaseIndex;
  }

  /// 构建完整的GetWordResult，包含单词详细信息、图片、时态等
  Future<Result<GetWordResult>> _buildGetWordResult({
    required User user,
    required LearningWord targetWordLearningData,
    required int nextLearningMode,
    required int nextWordIndex,
    required List<UserStudyStep> steps,
    required List<LearningWord> todayWords,
    required int modeCount,
    required MyDatabase db,
  }) async {
    try {
      // 获取单词详细信息 (Word table)
      final wordDetails = await db.wordsDao.getWordById(targetWordLearningData.wordId);
      if (wordDetails == null) {
        Global.logger.e('获取下一个单词失败: 单词详情不存在 (wordId: ${targetWordLearningData.wordId})');
        return Result("ERROR", "单词数据损坏", false);
      }

      // 构建WordVo (from wordDetails)
      final wordVo = WordVo.c2(wordDetails.spell);
      wordVo.id = wordDetails.id;
      wordVo.shortDesc = wordDetails.shortDesc;
      wordVo.longDesc = wordDetails.longDesc;
      wordVo.pronounce = wordDetails.pronounce;
      wordVo.americaPronounce = wordDetails.americaPronounce;
      wordVo.britishPronounce = wordDetails.britishPronounce;
      wordVo.popularity = wordDetails.popularity;

      // 获取单词的释义项
      final meaningItemsQuery = db.select(db.meaningItems)
        ..where((tbl) => tbl.wordId.equals(wordDetails.id))
        ..orderBy([(tbl) => OrderingTerm(expression: tbl.popularity)]);
      final meaningItems = await meaningItemsQuery.get();

      List<MeaningItemVo> meaningItemVos = [];
      for (final mi in meaningItems) {
        // 查询该释义项的例句
        final sentencesQuery = db.select(db.sentences)..where((s) => s.meaningItemId.equals(mi.id));
        final sentences = await sentencesQuery.get();

        List<SentenceVo> sentenceVos = [];
        for (final s in sentences) {
          final author = UserVo.c2(s.authorId);
          sentenceVos.add(SentenceVo(s.id, s.english, s.chinese, s.englishDigest, s.theType, s.footCount, s.handCount, author));
        }

        // 查询该释义项的同义词
        final synonymsQuery = db.select(db.synonyms)..where((syn) => syn.meaningItemId.equals(mi.id));
        final synonyms = await synonymsQuery.get();

        List<SynonymVo> synonymVos = [];
        for (final syn in synonyms) {
          // 获取同义词的单词信息
          final synWordQuery = db.select(db.words)..where((w) => w.id.equals(syn.wordId));
          final synWord = await synWordQuery.getSingleOrNull();

          if (synWord != null) {
            synonymVos.add(SynonymVo(null, syn.wordId, synWord.spell));
          }
        }

        meaningItemVos.add(MeaningItemVo(
            mi.id,
            mi.ciXing,
            mi.meaning,
            null, // dict
            synonymVos, // synonyms
            sentenceVos // sentences
            ));
      }
      wordVo.meaningItems = meaningItemVos;

      // 获取形近词
      final similarWordsQuery = db.select(db.similarWords)..where((sw) => sw.wordId.equals(wordDetails.id));
      final similarWords = await similarWordsQuery.get();

      List<WordVo> similarWordVos = [];
      for (final sw in similarWords) {
        final similarWordQuery = db.select(db.words)..where((w) => w.id.equals(sw.similarWordId));
        final similarWord = await similarWordQuery.getSingleOrNull();

        if (similarWord != null) {
          final similarWordVo = WordVo.c2(similarWord.spell);
          similarWordVo.id = similarWord.id;
          similarWordVo.shortDesc = similarWord.shortDesc;
          similarWordVo.longDesc = similarWord.longDesc;
          similarWordVo.pronounce = similarWord.pronounce;
          similarWordVo.americaPronounce = similarWord.americaPronounce;
          similarWordVo.britishPronounce = similarWord.britishPronounce;
          similarWordVo.popularity = similarWord.popularity;

          // 为形近词也获取基本释义项
          final simMeaningItemsQuery = db.select(db.meaningItems)
            ..where((tbl) => tbl.wordId.equals(similarWord.id))
            ..orderBy([(tbl) => OrderingTerm(expression: tbl.popularity)])
            ..limit(3); // 只取前3个释义项
          final simMeaningItems = await simMeaningItemsQuery.get();

          List<MeaningItemVo> simMeaningItemVos = [];
          for (final smi in simMeaningItems) {
            simMeaningItemVos.add(MeaningItemVo(
                smi.id,
                smi.ciXing,
                smi.meaning,
                null, // dict
                null, // synonyms
                null // sentences
                ));
          }
          similarWordVo.meaningItems = simMeaningItemVos;

          similarWordVos.add(similarWordVo);
        }
      }
      wordVo.similarWords = similarWordVos;

      // 构建LearningWordVo (using targetWordLearningData and wordVo)
      final userVoForLearningWord = UserVo.c2(user.id)..level = LevelVo(user.levelId);

      final learningWordVo = LearningWordVo(
          userVoForLearningWord,
          targetWordLearningData.addTime,
          targetWordLearningData.addDay,
          targetWordLearningData.lifeValue,
          targetWordLearningData.lastLearningDate,
          targetWordLearningData.learningOrder,
          targetWordLearningData.learnedTimes,
          wordVo);

      // 对于选择题学习模式, 需要获取2个混淆单词
      List<WordVo> otherWords = await getTwoOtherWords(steps, nextLearningMode, meaningItemVos, todayWords, targetWordLearningData, db);

      // 获取单词图片
      List<WordImageVo> wordImageVos = [];
      final wordImagesQuery = db.select(db.wordImages)..where((tbl) => tbl.wordId.equals(wordDetails.id));
      final wordImages = await wordImagesQuery.get();
      for (final img in wordImages) {
        // 获取作者信息
        final author = await db.usersDao.getUserById(img.authorId);
        if (author != null) {
          final authorVo = UserVo.c2(author.id)..nickName = author.nickName;
          wordImageVos.add(WordImageVo(
            img.id,
            img.imageFile,
            img.hand,
            img.foot,
            authorVo,
          ));
        }
      }

      // 获取单词时态
      List<VerbTenseVo> verbTenses = [];
      final verbTensesQuery = db.select(db.verbTenses)..where((tbl) => tbl.wordId.equals(wordDetails.id));
      final verbTensesData = await verbTensesQuery.get();
      for (final vt in verbTensesData) {
        verbTenses.add(VerbTenseVo(
          vt.id,
          wordVo,
          vt.tenseType,
          vt.tensedSpell ?? '',
        ));
      }

      // 计算学习进度
      final totalWordsToday = todayWords.length;
      // 计算当前学习索引
      final currentLearningIndex =
          calculateLearningIndexByWordIndexAndMode(nextWordIndex, nextLearningMode, modeCount, totalWordsToday, 10); // 每个阶段10个单词
      // 计算最大学习索引
      final maxLearningIndex = totalWordsToday * modeCount;
      // 计算当前进度
      final progress = [(totalWordsToday * ((currentLearningIndex + 1.0) / (maxLearningIndex + 1))).toInt(), totalWordsToday];

      // 构建GetWordResult
      return Result("SUCCESS", "获取成功", true)
        ..data = GetWordResult(
          learningWordVo,
          nextLearningMode, // current learningMode for the returned word
          otherWords,
          progress,
          wordDetails.pronounce,
          false, // finished (unless determined otherwise)
          false, // noWord (already handled)
          [], // cigens
          [], // additionalInfos
          [], // errorReports
          wordDetails.shortDesc,
          false, // shouldEnterReviewMode (already handled)
          wordImageVos,
          verbTenses,
          [], // shortDescChineses
          false, // inRawWordDict
          false, // wordMastered
        );
    } catch (e, stackTrace) {
      Global.logger.e('构建GetWordResult失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "构建单词信息失败: ${e.toString()}", false);
    }
  }

  /// 将单词标记为已掌握
  Future<void> _saveMasteredWord({
    required LearningWord learningWord,
    required User user,
    required DateTime now,
    required DateTime dateOnlyNow,
    required MyDatabase db,
    bool updateUserMasteredCount = false,
  }) async {
    // 把学习中单词生命值设置为0(已掌握)
    await db.learningWordsDao.saveEntity(
        learningWord.copyWith(
          lifeValue: 0,
          lastLearningDate: Value(dateOnlyNow),
          learnedTimes: learningWord.learnedTimes + 1,
        ),
        true);

    // 将单词添加到已掌握单词表
    await db.masteredWordsDao.saveMasteredWord(
        MasteredWord(
          userId: user.id,
          wordId: learningWord.wordId,
          masterAtTime: now,
          createTime: now,
          updateTime: now,
        ),
        true,
        true);

    // 如果需要，更新用户已掌握单词数量
    if (updateUserMasteredCount) {
      await db.usersDao.saveUser(
          user.copyWith(
            masteredWordsCount: user.masteredWordsCount + 1,
          ),
          true);
      ThrottledDbSyncService().requestSync();
    }
  }
}
