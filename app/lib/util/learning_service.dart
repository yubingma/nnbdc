import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:drift/drift.dart';
import 'package:nnbdc/util/date_utils.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/db/user_extensions.dart';

class LearningService {
  static void debugLog(String msg) {
    Global.logger.d(msg);
  }

  static const double initialStability = 0.0;
  static double get masteredStability => Constants.graduationStability;

  /// 准备今日学习单词
  static Future<Result<List<int>>> prepareTodayStudy(bool addNewWordsIfNotEnough) async {
    final user = Global.getLoggedInUser();
    if (user == null) {
      final result = Result<List<int>>('ERROR', '用户未登录', false);
      result.data = [0, 0];
      return result;
    }

    try {
      final db = MyDatabase.instance;

      // 如果用户的最近学习日期不是今天，重置相关数据
      final today = DateUtils.pureDate(AppClock.now());
      bool isNewDay = user.lastLearningDate == null || !DateUtils.isSameDay(user.lastLearningDate!, today);
      if (isNewDay) {
        Global.logger.d('检测到新的学习日期，开始重置用户数据: userId=${user.id}');

        // 新的一天开始时，删除已经掌握的学习中单词
        await db.learningWordsDao.deleteMasteredLearningWords(user.id);

        // 新的一天开始时，删除已经在 mastered_words 表中的学习单词
        await db.learningWordsDao.deleteMasteredWords(user.id);

        // 清空用户错词（新的一天开始，清空昨日错词）
        await db.userWrongWordsDao.clearUserWrongWords(user.id, true);
        Global.logger.d('已清空用户错词');

        // 直接通过数据库更新字段
        await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(UsersCompanion(
            lastLearningDate: Value(today),
            learnedDays: Value(user.learnedDays + 1),
            todayStudyStarted: const Value(false),
            learningFinished: const Value(false)));

        // 重置所有单词的今日学习次数和批次ID
        await (db.update(db.learningWords)..where((u) => u.userId.equals(user.id))).write(const LearningWordsCompanion(
          todayLearnedTimes: Value(0),
          batchId: Value(null),
        ));

        // 重新获取更新后的用户信息
        final updatedUser = await db.usersDao.getUserById(user.id);
        if (updatedUser != null) {
          // 清除缓存并重新加载
          Global.clearUserCache();
          await Global.loadUserFromDb();
        }

        Global.logger.d('用户数据重置完成');
      }

      // 尝试从数据库中读取今日学习单词
      List<LearningWord> todayWords = await getTodayLearningWordsFromDb(user.id);
      Global.logger.d('[FETCH-WORD] [prepareTodayStudy] 初始从DB获取到今日单词数: ${todayWords.length}, 目标计划: ${user.effectiveWordsPerDay}');

      // 生成(或补充)今日要学习的单词列表
      bool needAddNewWords = todayWords.isEmpty || (todayWords.length < (user.effectiveWordsPerDay) && addNewWordsIfNotEnough);
      Global.logger.d('[FETCH-WORD] [prepareTodayStudy] 是否需要补充单词: $needAddNewWords (todayWords.isEmpty: ${todayWords.isEmpty}, addNewWordsIfNotEnough: $addNewWordsIfNotEnough)');
      
      bool wordExhausted = false;
      if (needAddNewWords) {
        todayWords = await genTodayWords(user.id, AppClock.now(), todayWords);
        wordExhausted = todayWords.length < (user.effectiveWordsPerDay); 
        Global.logger.d('[FETCH-WORD] [prepareTodayStudy] genTodayWords执行后，内存中单词总数: ${todayWords.length}, 计划是否枯竭: $wordExhausted');
      }

    // 重新获取今日学习单词（确保获取的是当前DB中真实分配好batchId的数据）
    todayWords = await getTodayLearningWordsFromDb(user.id);
    Global.logger.d('[FETCH-WORD] [prepareTodayStudy] 重新从DB读取确认后的单词数: ${todayWords.length}');

      // 如果今日单词数量超过了设定的目标，需要削减（支持从计划页面调低数量）
      if (todayWords.length > user.effectiveWordsPerDay) {
        Global.logger.d('[FETCH-WORD] [prepareTodayStudy] 溢出报警！当前数 (${todayWords.length}) > 计划数 (${user.effectiveWordsPerDay})，准备进入削减逻辑');
        todayWords = await shrinkTodayWords(user.id, todayWords, user.effectiveWordsPerDay);
      }

      // 计算今日新词数
      int newWordCount = 0;
      for (var word in todayWords) {
        if (word.isTodayNewWord) {
          newWordCount++;
        }
      }

      final result = Result<List<int>>(wordExhausted ? 'NNBDC-0012' : '200', wordExhausted ? '未取到足够单词' : '成功', !wordExhausted);
      result.data = [newWordCount, todayWords.length - newWordCount];
      return result;
    } catch (e, stackTrace) {
      Global.logger.e('准备学习时出错: $e', stackTrace: stackTrace);
      ToastUtil.error('准备学习时出错: $e');
      final result = Result<List<int>>('ERROR', '准备学习时出错: $e', false);
      result.data = [0, 0];
      return result;
    }
  }

  /// 从数据库中获取已生成的用户今天要学习的单词列表
  static Future<List<LearningWord>> getTodayLearningWordsFromDb(String userId) async {
    final db = MyDatabase.instance;

    // 查询今天的学习单词 (只需按 batchId 过滤，因为新一天开始时 batchId 已重置)
    try {
      final query = db.select(db.learningWords)
        ..where((lw) =>
            lw.userId.equals(userId) &
            lw.batchId.isBiggerThanValue(0))
        ..orderBy([
          (lw) => OrderingTerm(expression: lw.batchId),
          (lw) => OrderingTerm(expression: lw.learningOrder),
        ]);

      final results = await query.get();
      Global.logger.d('[FETCH-WORD] [getTodayLearningWordsFromDb] SQL查询返回条数: ${results.length}, 关联的BatchIDs: ${results.map((e) => e.batchId).toSet()}');
      return results;
    } catch (e) {
      Global.logger.e('获取今日学习单词失败: $e');
      return [];
    }
  }

  /// 产生（或补充）今天要学习的单词列表，并把该列表更新到数据库
  static Future<List<LearningWord>> genTodayWords(String userId, DateTime now, List<LearningWord> todayLearningWords) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getUserById(userId);
    if (user == null) {
      throw Exception('用户不存在');
    }

    // 获取所有正在学习中的单词 (即：尚未毕业的候选人)
    final allLearningWords = await (db.select(db.learningWords)
          ..where((lw) => lw.userId.equals(userId) & lw.stability.isSmallerThanValue(Constants.graduationStability)))
        .get();

    // 排除今天已经选取要学的单词
    final List<LearningWord> candidateWords = List.from(allLearningWords);
    for (var todayWord in todayLearningWords) {
      candidateWords.removeWhere((word) => word.wordId == todayWord.wordId);
    }

    // 1. 识别到期单词 (Due Words)
    final today = DateTime(now.year, now.month, now.day);
    bool isDue(LearningWord word) {
      if (word.lastLearningDate == null) return true; // 全新词未在当前算法下学习过

      // FSRS 逻辑：上次学习日期 + 计划天数 <= 今天
      final nextReviewDate = DateTime(
        word.lastLearningDate!.year,
        word.lastLearningDate!.month,
        word.lastLearningDate!.day,
      ).add(Duration(days: word.scheduledDays ?? 0));

      return nextReviewDate.isBefore(today) || DateUtils.isSameDay(nextReviewDate, today);
    }

    final List<LearningWord> dueWords = candidateWords.where(isDue).toList();

    // 到期单词内部排序逻辑：
    // - 处于 Review 状态的优先于新词，稳定性越低的单词越需要优先复习
    dueWords.sort((a, b) {
      if ((a.stability ?? 0.0) != (b.stability ?? 0.0)) {
        return (a.stability ?? 0.0).compareTo(b.stability ?? 0.0);
      }
      return a.addTime.compareTo(b.addTime);
    });

    // 产生批次 ID
    int maxBatchId = 0;
    if (todayLearningWords.isNotEmpty) {
      for (var w in todayLearningWords) {
        if ((w.batchId ?? 0) > maxBatchId) maxBatchId = w.batchId!;
      }
    }
    int targetBatchId = maxBatchId == 0 ? 1 : maxBatchId + 1;

    // 2. 将到期单词加入今日计划，直到达到用户设定的每日目标
    int dueAddedCount = 0;
    for (var word in dueWords) {
      if (todayLearningWords.length >= user.effectiveWordsPerDay) {
        Global.logger.d('[FETCH-WORD] [genTodayWords] 到期复习词已填满计划 (${user.effectiveWordsPerDay})');
        break;
      }
      todayLearningWords.add(word.copyWith(batchId: Value(targetBatchId)));
      dueAddedCount++;
    }
    Global.logger.d('[FETCH-WORD] [genTodayWords] 本批次 ($targetBatchId) 新增复习词: $dueAddedCount, 当前总数: ${todayLearningWords.length}');

    // 3. 如果依然没取够，则从词书按顺序抓取绝对的新词来补足以撑起今日计划
    if (todayLearningWords.length < user.effectiveWordsPerDay) {
      // 确定 addDay 序号
      LearningWord? latestWord;
      for (var word in allLearningWords) {
        if (latestWord == null || word.addTime.isAfter(latestWord.addTime)) {
          latestWord = word;
        }
      }
      int todayDayNumber = 1;
      if (latestWord != null) {
        todayDayNumber = DateUtils.isSameDay(latestWord.addTime, now) ? latestWord.addDay : latestWord.addDay + 1;
      }

      int needNewCount = user.effectiveWordsPerDay - todayLearningWords.length;
      Global.logger.d('[FETCH-WORD] [genTodayWords] 计划未满，准备新抓取单词，缺额: $needNewCount');

      final newWords = await fetchNewWordsToLearn(userId, todayDayNumber, needNewCount);
      Global.logger.d('[FETCH-WORD] [genTodayWords] 实际抓取到新词: ${newWords.length} 个');
      for (var word in newWords) {
        todayLearningWords.add(word.copyWith(batchId: Value(targetBatchId)));
      }
    }

    // 将今日的学习单词分配好顺序并更新到数据库
    await updateTodayLearningWords(todayLearningWords, now);

    return todayLearningWords;
  }


  /// 削减今日学习单词（当用户调低每日单词量时）
  static Future<List<LearningWord>> shrinkTodayWords(String userId, List<LearningWord> todayWords, int targetCount) async {
    final db = MyDatabase.instance;

    // 1. 甄别哪些单词是可以被移除的（今天还没开始学的词）
    List<LearningWord> untaughtWords = todayWords.where((w) => w.todayLearnedTimes == 0).toList();
    List<LearningWord> learnedWords = todayWords.where((w) => w.todayLearnedTimes > 0).toList();

    // 如果即便把还没学的词全删了，剩下的词依然超过目标（说明用户今天已经学了很多了），那我们也无法强行删除已学的词
    if (learnedWords.length >= targetCount) {
      Global.logger.d('[FETCH-WORD] [shrinkTodayWords] 无法削减！已学单词数 (${learnedWords.length}) 已 >= 目标 ($targetCount)');
      return todayWords; 
    }

    Global.logger.d('[FETCH-WORD] [shrinkTodayWords] 执行削减：当前 ${todayWords.length} -> 目标 $targetCount, 计划移除 ${todayWords.length - targetCount} 个未学单词');

    // 2. 计算需要移除的数量
    int needToRemove = todayWords.length - targetCount;
    
    // 3. 排序待移除的单词：按 batchId 降序，然后再按 learningOrder 降序（先移除后面批次的，再移除批次内靠后的）
    untaughtWords.sort((a, b) {
      if (a.batchId != b.batchId) {
        return (b.batchId ?? 0).compareTo(a.batchId ?? 0);
      }
      return b.learningOrder.compareTo(a.learningOrder);
    });

    // 4. 执行移除逻辑
    List<LearningWord> wordsToRemove = untaughtWords.take(needToRemove).toList();
    List<LearningWord> remainingUntaughtWords = untaughtWords.skip(needToRemove).toList();

    for (var word in wordsToRemove) {
      // 通过将 batchId 设为 0 并清空 lastLearningDate，使其不再出现在今日列表中
      await db.learningWordsDao.saveEntity(
        word.copyWith(
          batchId: const Value(0),
          lastLearningDate: const Value(null),
          learningOrder: 0,
        ),
        true,
      );
    }

    Global.logger.d('已成功移除 $needToRemove 个未学习单词');

    // 5. 合并并返回剩余的单词
    List<LearningWord> finalWords = [...learnedWords, ...remainingUntaughtWords];
    
    // 重新校正剩余单词的 learningOrder
    finalWords.sort((a, b) {
      if (a.batchId != b.batchId) {
        return (a.batchId ?? 0).compareTo(b.batchId ?? 0);
      }
      return a.learningOrder.compareTo(b.learningOrder);
    });

    for (int i = 0; i < finalWords.length; i++) {
        finalWords[i] = finalWords[i].copyWith(learningOrder: i + 1);
        await db.learningWordsDao.saveEntity(finalWords[i], true);
    }

    return finalWords;
  }

  /// 将今日的学习单词更新到数据库
  static Future<void> updateTodayLearningWords(List<LearningWord> todayLearningWords, DateTime now) async {
    final db = MyDatabase.instance;
    if (todayLearningWords.isEmpty) return;

    // 1. 找出当前最大的 batchId
    int maxBatchId = 1;
    for (var w in todayLearningWords) {
      if ((w.batchId ?? 0) > maxBatchId) maxBatchId = w.batchId!;
    }

    // 2. 排序逻辑：
    // 首先按照 batchId 升序排列。
    // 对于最新批次 (batchId == maxBatchId)，内部按照 stability 升序排列。
    // 对于旧批次，内部保持原有的 learningOrder 顺序。
    todayLearningWords.sort((a, b) {
      if (a.batchId != b.batchId) {
        return (a.batchId ?? 0).compareTo(b.batchId ?? 0);
      }
      if (a.batchId == maxBatchId) {
        // 最新批次：掌握度升序
        return (a.stability ?? 0.0).compareTo(b.stability ?? 0.0);
      }
      // 旧批次：既有学习顺序升序
      return a.learningOrder.compareTo(b.learningOrder);
    });

    // 3. 全局刷新 learningOrder 并保存
    try {
      for (int i = 0; i < todayLearningWords.length; i++) {
        var learningWord = todayLearningWords[i];

        // 统一更新日期标记（如果是第一次加入今天的批次）
        // 不再预更新 lastLearningDate，保留其原始值用于 FSRS 间隔计算
        if (learningWord.isTodayNewWord != (learningWord.learnedTimes == 0)) {
          learningWord = learningWord.copyWith(
            isTodayNewWord: learningWord.learnedTimes == 0,
          );
        }

        // 重新分配全局连续的学习顺序
        learningWord = learningWord.copyWith(learningOrder: i + 1);

        todayLearningWords[i] = learningWord;
        await db.learningWordsDao.saveEntity(learningWord, true);
      }

      Global.logger.d('今日学习单词全局重排完成，共更新 ${todayLearningWords.length} 个单词');
    } catch (e, stackTrace) {
      Global.logger.d('更新今日学习单词时出错: $e');
      Global.logger.d('异常堆栈: $stackTrace');
      rethrow;
    }
  }



  /// 从词书取新词（支持优先级和已掌握过滤）
  static Future<List<LearningWord>> fetchNewWordsToLearn(String userId, int todayDayNumber, int countToFetch) async {
    if (countToFetch <= 0) {
      return [];
    }

    final db = MyDatabase.instance;

    // 获取用户选择的词书，按优先级排序（优先取词的书排在前面）
    final learningDicts = await (db.select(db.learningDicts)
          ..where((ld) => ld.userId.equals(userId))
          ..orderBy([(ld) => OrderingTerm.desc(ld.isPrivileged), (ld) => OrderingTerm.asc(ld.createTime)]))
        .get();

    if (learningDicts.isEmpty) {
      return [];
    }

    // 获取用户已掌握的单词
    final masteredWords = await db.masteredWordsDao.getMasteredWordsForUser(userId);
    final masteredWordIds = masteredWords.map((w) => w.wordId).toList();

    // 获取用户已学习的单词ID
    final existingLearningWords = await (db.select(db.learningWords)..where((lw) => lw.userId.equals(userId))).get();
    final existingWordIds = existingLearningWords.map((w) => w.wordId).toSet();

    // 按优先级顺序处理词书
    List<LearningWord> learningWords = [];

    for (var learningDict in learningDicts) {
      if (learningWords.length >= countToFetch) break;

      // 获取词书信息
      final dict = await db.dictsDao.findById(learningDict.dictId);
      if (dict == null) continue;

      // 查询词书所有单词，按 seq 顺序
      final dictWords = await (db.select(db.dictWords)
            ..where((dw) => dw.dictId.equals(learningDict.dictId))
            ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
          .get();

      for (var dictWord in dictWords) {
        if (learningWords.length >= countToFetch) break;

        // 判断该单词是否已经在学习中
        if (existingWordIds.contains(dictWord.wordId)) continue;

        // 判断该单词是否已经掌握（根据fetchMastered设置决定）
        if (!learningDict.fetchMastered && masteredWordIds.contains(dictWord.wordId)) continue;

        // 创建新的LearningWord
        final now = AppClock.now();
        final learningWord = LearningWord(
            userId: userId,
            wordId: dictWord.wordId,
            addTime: now,
            addDay: todayDayNumber,
            stability: null, // FSRS 初始状态设为 null
            difficulty: null,
            elapsedDays: null,
            scheduledDays: null,
            reps: null,
            lapses: null,
            state: 0, // 0: New
            batchId: 0, // 初始批次设为 0，只有加入今日学习时才分配有效批次
            lastLearningDate: null, // 与后端逻辑一致，初始化为null
            learningOrder: 0,
            isTodayNewWord: false,
            learnedTimes: 0,
            todayLearnedTimes: 0,
            createTime: now,
            updateTime: now);

        // 保存到数据库
        await db.learningWordsDao.saveEntity(learningWord, true);
        learningWords.add(learningWord);
      }
    }

    return learningWords;
  }
}
