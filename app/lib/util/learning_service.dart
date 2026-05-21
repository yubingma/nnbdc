import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:drift/drift.dart';
import 'package:nnbdc/util/date_utils.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/db/user_extensions.dart';
import 'package:nnbdc/services/study_cache_manager.dart';

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
      final today = DateUtils.businessDate(AppClock.now());
      bool isNewDay = user.lastLearningDate == null || user.lastLearningDate != today;
      Global.logger.i('prepareTodayStudy 今日学习准备：user.lastLearningDate=${user.lastLearningDate}, today=$today, isNewDay=$isNewDay, now=${AppClock.now()}');

      // [核心修复] 自动修复机制：即使日期没变，但如果发现"学习未开始"且"单词已有进度"这种不一致状态，也强制重置。
      bool needRepair = (user.todayStudyStarted == false);
      if (needRepair) {
        final inconsistencyCheck = await (db.select(db.learningWords)
              ..where((lw) => lw.userId.equals(user.id) & lw.todayLearnedTimes.isBiggerThanValue(0))
              ..limit(1))
            .get();
        needRepair = inconsistencyCheck.isNotEmpty;
        if (needRepair) {
          Global.logger.w('检测到数据不一致：日期已对上且学习未开始，但发现存在单词进度。触发强制修复重置修复。');
        }
      }

      if (isNewDay || needRepair) {
        Global.logger.d('开始重置用户每日数据（isNewDay=$isNewDay, repair=$needRepair）: userId=${user.id}');

        // 使用事务确保整个重置过程的原子性：要么全部完成，要么全部失败
        await db.transaction(() async {
          // 1. 重置所有待同步的单词数据 (昨日计划分配、产生过今日进度的、或是已经掌握的)
          // 注意：此处必须要清空所有 batch_id > 0 的词，确保重新按 FSRS 进度分配
          final needResetWords = await (db.select(db.learningWords)
                ..where((lw) =>
                    lw.userId.equals(user.id) &
                    (lw.todayLearnedTimes.isBiggerThanValue(0) | lw.batchId.isBiggerThanValue(0))))
              .get();

          for (var word in needResetWords) {
            await db.learningWordsDao.saveEntity(
                word.copyWith(
                  todayLearnedTimes: 0,
                  batchId: const Value(0),
                  learningOrder: 0,
                ),
                true // 强制生成同步记录，更新云端
                );
          }

          // 2. 清理相关联表 (在此处集中处理)
          await db.learningWordsDao.deleteMasteredLearningWords(user.id); // 删除已掌握的学习中单词
          await db.learningWordsDao.deleteMasteredWords(user.id); // 删除已经在 mastered_words 表中的学习单词
          await db.userWrongWordsDao.clearUserWrongWords(user.id, true); // 清空错词

          // 3. 最后一步：更新用户信息，并标记重置已完成 (这一步完成后，下次重入将不再进入重置逻辑)
          final upgradedUser = user.copyWith(
              lastLearningDate: Value(today), // 标记, 防止再次重置
              learnedDays: isNewDay ? user.learnedDays + 1 : user.learnedDays, // 仅新的一天增加天数
              learningFinished: const Value(false),
              todayStudyStarted: false,
              todayLearningSeconds: const Value(0));
          await db.usersDao.saveUser(upgradedUser, true);
        });

        // 刷新缓存
        Global.clearUserCache();
        await Global.loadUserFromDb();
        Global.logger.d('用户每日数据重置成功');
      }

      // 尝试从数据库中读取今日学习单词
      List<LearningWord> todayWords = await getTodayLearningWordsFromDb(user.id);
      Global.logger.d('[FETCH-WORD] [prepareTodayStudy] 初始从DB获取到今日单词数: ${todayWords.length}, 目标计划: ${user.effectiveWordsPerDay}');

      // 生成(或补充)今日要学习的单词列表
      bool needAddNewWords = todayWords.isEmpty || (todayWords.length < (user.effectiveWordsPerDay) && addNewWordsIfNotEnough);
      Global.logger.d(
          '[FETCH-WORD] [prepareTodayStudy] 是否需要补充单词: $needAddNewWords (todayWords.isEmpty: ${todayWords.isEmpty}, addNewWordsIfNotEnough: $addNewWordsIfNotEnough)');

      bool wordExhausted = false;
      if (needAddNewWords) {
        todayWords = await genTodayWords(user.id, AppClock.now(), todayWords);
        wordExhausted = todayWords.length < (user.effectiveWordsPerDay);
        Global.logger.d('[FETCH-WORD] [prepareTodayStudy] genTodayWords执行后，内存中单词总数: ${todayWords.length}, 计划是否枯竭: $wordExhausted');
      }


      if (todayWords.length > user.effectiveWordsPerDay) {
        Global.logger.d('[FETCH-WORD] [prepareTodayStudy] 溢出报警！当前数 (${todayWords.length}) > 计划数 (${user.effectiveWordsPerDay})，准备进入削减逻辑');
        todayWords = await shrinkTodayWords(user.id, todayWords, user.effectiveWordsPerDay);
      }

      // 最后统一校正标记并刷新学习顺序（处理已经分配在DB但需要纠零标记的数据，以及在调整目标后重排顺序）
      await updateTodayLearningWords(todayWords, AppClock.now());

      // 计算今日新词数
      int newWordCount = 0;
      for (var word in todayWords) {
        if (word.isTodayNewWord) {
          newWordCount++;
        }
      }

      StudyCacheManager().clear();

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
        ..where((lw) => lw.userId.equals(userId) & lw.batchId.isBiggerThanValue(0))
        ..orderBy([
          (lw) => OrderingTerm(expression: lw.batchId),
          (lw) => OrderingTerm(expression: lw.learningOrder),
        ]);

      final results = await query.get();
      Global.logger
          .d('[FETCH-WORD] [getTodayLearningWordsFromDb] SQL查询返回条数: ${results.length}, 关联的BatchIDs: ${results.map((e) => e.batchId).toSet()}');
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
          ..where((lw) => lw.userId.equals(userId) & (lw.stability.isNull() | lw.stability.isSmallerThanValue(Constants.graduationStability))))
        .get();

    // 排除今天已经选取要学的单词
    final Set<String> todayWordIds = todayLearningWords.map((e) => e.wordId).toSet();
    final List<LearningWord> candidateWords = allLearningWords.where((word) => !todayWordIds.contains(word.wordId)).toList();

    // 1. 识别到期单词 (Due Words)
    final today = AppClock.today();
    bool isDue(LearningWord word) {
      if (word.lastLearningDate == null) return true; // 全新词未在当前算法下学习过

      // FSRS 逻辑：上次学习日期 + 计划天数 <= 今天
      final lastDate = DateUtils.businessDate(word.lastLearningDate!);
      final nextReviewDate = lastDate.add(Duration(days: word.scheduledDays ?? 0));

      return nextReviewDate.isBefore(today) || DateUtils.isSameDay(nextReviewDate, today);
    }

    final List<LearningWord> dueWords = candidateWords.where(isDue).toList();

    // 到期单词内部排序逻辑：
    // - 处于 Review 状态的优先于新词，稳定性越低的单词越需要优先复习
    dueWords.sort((a, b) {
      // 1. 状态权重：正在学习/复习中的单词 (state > 0) 优先于全新词 (state == 0)
      final aIsEstablished = (a.state ?? 0) > 0;
      final bIsEstablished = (b.state ?? 0) > 0;
      if (aIsEstablished != bIsEstablished) {
        return aIsEstablished ? -1 : 1; // 建立过进度的优先
      }

      // 2. 稳定性权重：稳定性越低(越容易忘记)的优先
      if ((a.stability ?? 0.0) != (b.stability ?? 0.0)) {
        return (a.stability ?? 0.0).compareTo(b.stability ?? 0.0);
      }

      // 3. 时间权重：添加日期更久的优先
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
      todayLearningWords.add(word.copyWith(batchId: Value(targetBatchId), learningOrder: 0));
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
        todayLearningWords.add(word.copyWith(batchId: Value(targetBatchId), learningOrder: 0));
      }
    }


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
      // 仅通过将 batchId 设为 0 使其不再出现在今日列表中，绝对不能清空 lastLearningDate (会破坏 FSRS)
      await db.learningWordsDao.saveEntity(
        word.copyWith(
          batchId: const Value(0),
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

    // 断言：如果今日尚未开始学习，虽然有了计划，但每个计划中单词的今日学习次数必为零
    if (Global.getLoggedInUser()?.todayStudyStarted == false) {
      for (var word in todayLearningWords) {
        assert(word.todayLearnedTimes == 0,
            '数据不一致：今日尚未开始学习，但单词 ${word.wordId} 已发现今日进度 (${word.todayLearnedTimes})');
      }
    }

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

      // 核心修复逻辑：
      // 1. 如果已经有学习顺序了（learningOrder > 0），说明该批次之前已经初始化过，
      //    为了保持学习序列的稳定性（防止在同一天多次重入时，因为单词掌握度变化导致顺序跳变），固定沿用既有顺序。
      if (a.learningOrder > 0 && b.learningOrder > 0) {
        final cmp = a.learningOrder.compareTo(b.learningOrder);
        if (cmp != 0) return cmp;
        return a.wordId.compareTo(b.wordId);
      }

      // 2. 如果是尚未初始化的新批次（learningOrder == 0），则按掌握度（stability）升序排列，
      //    确保在该批次内部，用户先学习最陌生的单词。
      final cmp = (a.stability ?? 0.0).compareTo(b.stability ?? 0.0);
      if (cmp != 0) return cmp;
      return a.wordId.compareTo(b.wordId);
    });

    // 3. 全局刷新 learningOrder 并保存
    try {
      for (int i = 0; i < todayLearningWords.length; i++) {
        var learningWord = todayLearningWords[i];

        // 统一更新日期标记（如果是第一次加入今天的批次）
        // 不再预更新 lastLearningDate，保留其原始值用于 FSRS 间隔计算
        // 只有当单词今天还没产生学习记录时，才修正 isTodayNewWord 标记。
        // 否则如果白天学过了一次，learnedTimes 变为了 1，这里会导致标记被重置为 false，导致进度统计错误。
        if (learningWord.todayLearnedTimes == 0) {
          // 判断是否为今日新词：从未学习过（learnedTimes == 0）且没有 FSRS 进度 (lastLearningDate == null)
          bool shouldBeNewWord = learningWord.learnedTimes == 0 && learningWord.lastLearningDate == null;
          if (learningWord.isTodayNewWord != shouldBeNewWord) {
            learningWord = learningWord.copyWith(
              isTodayNewWord: shouldBeNewWord,
            );
          }
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

    Global.logger.d('[FETCH-NEW-WORDS] 开始抓取新词, 目标数量: $countToFetch, 针对日期序号: $todayDayNumber');

    final db = MyDatabase.instance;

    // 获取用户选择的词书，按优先级排序（优先取词的书排在前面）
    final learningDicts = await (db.select(db.learningDicts)
          ..where((ld) => ld.userId.equals(userId))
          ..orderBy([(ld) => OrderingTerm.desc(ld.isPrivileged), (ld) => OrderingTerm.asc(ld.createTime)]))
        .get();

    if (learningDicts.isEmpty) {
      Global.logger.w('[FETCH-NEW-WORDS] 没有已激活的词书，退出抓取');
      return [];
    }

    // 获取用户已掌握的单词 ID（作为排除项）
    final masteredWordIdsSet = await db.masteredWordsDao.getMasteredWordIdSet(userId);

    // 获取用户已学习的单词 ID（作为排除项）
    final rows = await (db.selectOnly(db.learningWords)
          ..addColumns([db.learningWords.wordId])
          ..where(db.learningWords.userId.equals(userId)))
        .get();
    final existingWordIdsSet = rows.map((row) => row.read(db.learningWords.wordId)!).toSet();

    Global.logger.d('[FETCH-NEW-WORDS] 排除项准备完毕: 已掌握 ${masteredWordIdsSet.length} 个, 学习中 ${existingWordIdsSet.length} 个');

    // 按优先级顺序处理词书
    List<LearningWord> learningWords = [];

    for (var learningDict in learningDicts) {
      if (learningWords.length >= countToFetch) break;

      Global.logger.d('[FETCH-NEW-WORDS] 正在处理词书: ${learningDict.dictId}');

      // 查询词书单词，按 seq 顺序批量处理
      const int batchSize = 1000;
      int offset = 0;
      bool hasMoreInDict = true;

      while (hasMoreInDict && learningWords.length < countToFetch) {
        final dictWords = await (db.select(db.dictWords)
              ..where((dw) => dw.dictId.equals(learningDict.dictId))
              ..orderBy([(dw) => OrderingTerm.asc(dw.seq)])
              ..limit(batchSize, offset: offset))
            .get();

        if (dictWords.isEmpty) {
          hasMoreInDict = false;
          break;
        }

        Global.logger.d('[FETCH-NEW-WORDS] 从词书 ${learningDict.dictId} 读取到批次 (size=${dictWords.length}, offset=$offset)');

        for (var dictWord in dictWords) {
          if (learningWords.length >= countToFetch) break;

          final wordId = dictWord.wordId;

          // 判断该单词是否已经在学习中 (O(1) lookup in Set)
          if (existingWordIdsSet.contains(wordId)) continue;

          // 判断该单词是否已经掌握 (O(1) lookup in Set)
          if (!learningDict.fetchMastered && masteredWordIdsSet.contains(wordId)) continue;

          // 创建新的LearningWord
          final now = AppClock.now();
          final learningWord = LearningWord(
              userId: userId,
              wordId: wordId,
              addTime: now,
              addDay: todayDayNumber,
              stability: null, // FSRS 初始状态设为 null
              difficulty: null,
              elapsedDays: null,
              scheduledDays: null,
              reps: null,
              lapses: null,
              state: 0, // 0: New
              batchId: 0,
              lastLearningDate: null,
              learningOrder: 0,
              isTodayNewWord: true, // 这是新抓取的，肯定是今日新词
              learnedTimes: 0,
              todayLearnedTimes: 0,
              createTime: now,
              updateTime: now);

          // 保存到数据库 (注意：这可能会频繁生成日志，若性能依然不理想，考虑将 batchId 分配挪到外部一并保存)
          await db.learningWordsDao.saveEntity(learningWord, true);
          learningWords.add(learningWord);
        }

        offset += batchSize;
        if (dictWords.length < batchSize) {
          hasMoreInDict = false;
        }
      }
    }

    Global.logger.d('[FETCH-NEW-WORDS] 抓取完成，共抓取到 ${learningWords.length} 个新词');
    return learningWords;
  }
}
