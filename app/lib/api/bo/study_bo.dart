import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/util/distractor_strategy.dart';
import 'package:nnbdc/util/study_track.dart';
import 'package:nnbdc/util/study_config.dart';
import 'package:nnbdc/util/study_steps_service.dart';
import 'package:nnbdc/util/learning_service.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/db/learning_word_extensions.dart';
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
import 'package:nnbdc/util/sound.dart';

/// 业务对象（BO）：承载本地实现逻辑
class StudyBo {
  final StudyStepsService _studyStepsService = StudyStepsService();
  static final StudyBo _instance = StudyBo._internal();

  factory StudyBo() {
    return _instance;
  }

  StudyBo._internal();
  

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

      // 查询今日已分配批次的单词 (batchId > 0 表示该词属于今日学习计划)
      final query = db.select(db.learningWords)
        ..where((tbl) => tbl.userId.equals(user.id) & tbl.batchId.isBiggerThanValue(0))
        ..orderBy([
          (tbl) => OrderingTerm(expression: tbl.batchId),
          (tbl) => OrderingTerm(expression: tbl.learningOrder),
        ]);
      final todayWords = await query.get();

      // 获取学习步骤（用于构造每词的环节轨道）
      final newCfg = await _studyStepsService.getThreeGroupConfig('new');
      final reviewCfg = await _studyStepsService.getThreeGroupConfig('review');

      // 获取用户已掌握的单词（状态驱动）
      final masteredWords = await db.masteredWordsDao.getMasteredWordsForUser(user.id);
      final masteredWordIds = masteredWords.map((e) => e.wordId).toSet();

      // 状态驱动：推导当前批次起始位置 (batchStartIndex)
      const int batchSize = 10;
      final firstLogs =
          await _loadTodayFirstLogs(user.id, todayWords);
      int batchStartIndex = _calculateBatchStartIndex(todayWords, masteredWordIds,
          firstLogs: firstLogs,
          newCfg: newCfg,
          reviewCfg: reviewCfg,
          batchSize: batchSize);
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

      var todayWords = await StudyCacheManager().getTodayWords(db, user.id);

      if (todayWords.isEmpty) {
        return Result("ERROR", "今日没有学习单词", false);
      }

      final newCfg = await _studyStepsService.getThreeGroupConfig('new');
      final reviewCfg = await _studyStepsService.getThreeGroupConfig('review');

      // 计算掌握情况（状态驱动）
      final masteredWords = await db.masteredWordsDao.getMasteredWordsForUser(user.id);
      final masteredWordIds = masteredWords.map((e) => e.wordId).toSet();

      // 计算 batchStartIndex
      final firstLogs =
          await _loadTodayFirstLogs(user.id, todayWords);
      final batchStartIndex = _calculateBatchStartIndex(todayWords, masteredWordIds,
          firstLogs: firstLogs,
          newCfg: newCfg,
          reviewCfg: reviewCfg,
          batchSize: 10);
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
        // 按该词自身轨道判断当前环节是否为 List（复习词轨道与学习词轨道不同）
        final first = firstLogs[word.wordId];
        final track = StudyTrack.trackOf(
          stability: word.stability,
          state: word.state,
          lastLearningDate: word.lastLearningDate,
          todayFirstLogElapsedDays: first?.elapsedDays,
          todayFirstLogRating: first?.rating,
          newCheck: newCfg.check,
          newCorrect: newCfg.correct,
          newWrong: newCfg.wrong,
          reviewCheck: reviewCfg.check,
          reviewCorrect: reviewCfg.correct,
          reviewWrong: reviewCfg.wrong,
          today: AppClock.today(),
        );
        int currentStepIndex = word.todayLearnedTimes;
        if (currentStepIndex < track.length && track[currentStepIndex] == 'List') {
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

      // 实时获取数据库里的最新数据，防止缓存未同步带来的误判
      final dbUser = await db.usersDao.getUserById(user.id);
      if (dbUser != null) {
        bool needUpdate = false;
        if (user.todayStudyStarted != dbUser.todayStudyStarted) {
          needUpdate = true;
        } else if ((user.lastLearningDate == null && dbUser.lastLearningDate != null) ||
            (user.lastLearningDate != null && dbUser.lastLearningDate == null)) {
          needUpdate = true;
        } else if (user.lastLearningDate != null && dbUser.lastLearningDate != null) {
          // 在业务日期不同的情况下才认为是不一致，防止因为 Local/UTC 标志及微秒级误差导致的误判
          if (!DateUtils.isSameBusinessDay(user.lastLearningDate!, dbUser.lastLearningDate!)) {
            needUpdate = true;
          }
        }

        if (needUpdate) {
          Global.logger.w('⚠️ [StudyBo-DateCheck] [警告] 检测到全局内存缓存与数据库内容不一致！\n'
              '内存缓存：lastLearningDate=${user.lastLearningDate} (isUtc: ${user.lastLearningDate?.isUtc}), todayStudyStarted=${user.todayStudyStarted}\n'
              'SQLite数据库：lastLearningDate=${dbUser.lastLearningDate} (isUtc: ${dbUser.lastLearningDate?.isUtc}), todayStudyStarted=${dbUser.todayStudyStarted}\n'
              '系统已自动修正内存缓存！');
          Global.updateUserCache(dbUser);
        }
      }

      // 获取最终确定的用于计算的用户状态
      final currentUser = Global.getLoggedInUser() ?? user;
      final bool isSameDay = currentUser.lastLearningDate != null &&
          DateUtils.isSameBusinessDay(currentUser.lastLearningDate!, today);

      Global.logger.i('💡 [StudyBo-DateCheck] 跨天检测全链路详情：\n'
          '  - 账号ID: ${currentUser.id}\n'
          '  - 内存 user.lastLearningDate: ${user.lastLearningDate} (isUtc: ${user.lastLearningDate?.isUtc})\n'
          '  - 数据库 dbUser.lastLearningDate: ${dbUser?.lastLearningDate} (isUtc: ${dbUser?.lastLearningDate?.isUtc})\n'
          '  - 判定使用 lastLearningDate: ${currentUser.lastLearningDate} (isUtc: ${currentUser.lastLearningDate?.isUtc})\n'
          '  - 判定使用 today: $today (isUtc: ${today.isUtc})\n'
          '  - 时区及日期对比 (isSameDay): $isSameDay\n'
          '  - 是否触发跨天逻辑: ${currentUser.lastLearningDate != null && !isSameDay}');

      final lastDate = currentUser.lastLearningDate != null
          ? DateUtils.businessDate(currentUser.lastLearningDate!)
          : null;
      // 必须是已开始今日学习，且上一次学习日期严格早于今日业务日期时，才判定为跨天
      final bool isCrossDay = currentUser.todayStudyStarted &&
          lastDate != null &&
          lastDate.isBefore(today);

      if (isCrossDay) {
        Global.logger.w('🛑 [StudyBo-DateCheck] [触发跨天] 判定跨天成功：最近学习业务日期 $lastDate 早于今日业务日期 $today！触发 NEW_DAY 终止学习流程！');
        return Result<GetWordResult>("NEW_DAY", "已进入新的一天，今天的学习已终止", false);
      }

      final swSteps = Stopwatch()..start();
      // 获取用户的学习步骤配置
      final newCfg = await _studyStepsService.getThreeGroupConfig('new');
      final reviewCfg = await _studyStepsService.getThreeGroupConfig('review');
      if (newCfg.check.isEmpty) {
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

      // 查询今天首条评分日志（间隔+评分）：固化每个词的当天轨道（学习/复习），当天不漂移
      final firstLogs =
          await _loadTodayFirstLogs(user.id, todayWords);
      // 旧词三组显式规则（未设置时轨道层回退默认）

      // 状态驱动：推导当前批次起始位置 (batchStartIndex)
      const int batchSize = 10;
      int batchStartIndex = _calculateBatchStartIndex(todayWords, masteredWordIds,
          firstLogs: firstLogs,
          newCfg: newCfg,
          reviewCfg: reviewCfg,
          batchSize: batchSize);
      if (batchStartIndex == -1) {
        return _buildTodayStudyFinishedResult();
      }

      // 获取当前批次的 10 个词
      List<LearningWord> batchWords = [];
      for (int i = batchStartIndex; i < todayWords.length && i < batchStartIndex + batchSize; i++) {
        batchWords.add(todayWords[i]);
      }

      // 异步在后台线程加载拼写并执行音频预取，不阻塞 getWord 的返回
      if (batchWords.isNotEmpty) {
        unawaited(() async {
          try {
            final wordIds = batchWords.map((bw) => bw.wordId).toList();
            final wordsList = await db.wordsDao.getWordsByIds(wordIds);
            final urls = wordsList.map((w) => Util.getWordSoundUrl(w.spell, word: WordVo.c2(w.spell)..id = w.id)).toList();
            if (urls.isNotEmpty) {
              SoundUtil.prefetchSounds(urls);
            }
          } catch (e) {
            Global.logger.w('StudyBo: 后台预取音频失败: $e');
          }
        }());
      }

      // 轨道推导 helper：每个词按状态走学习轨道（激活序列）或复习轨道（测评+答对/答错组+List）。
      // 轨道由"今天首条评分日志的 elapsedDays"固化（init=0 → 学习轨道；跨天 next>0 → 复习轨道），
      // 当天后续评分不再改变轨道，防止 state 变化导致轨道中途漂移。
      List<String> trackOf(LearningWord word) {
        final first = firstLogs[word.wordId];
        return StudyTrack.trackOf(
          stability: word.stability,
          state: word.state,
          lastLearningDate: word.lastLearningDate,
          todayFirstLogElapsedDays: first?.elapsedDays,
          todayFirstLogRating: first?.rating,
          newCheck: newCfg.check,
          newCorrect: newCfg.correct,
          newWrong: newCfg.wrong,
          reviewCheck: reviewCfg.check,
          reviewCorrect: reviewCfg.correct,
          reviewWrong: reviewCfg.wrong,
          today: today,
        );
      }

      // 添加批次状态日志
      Global.logger.d('~~~~~BDC_BATCH: startIdx=$batchStartIndex, batchSize=${batchWords.length}');
      for (var w in batchWords) {
        final bool isMastered = w.isEffectivelyMastered(masteredWordIds);
        final bool isFinished = w.isTodayFinished(masteredWordIds, trackOf(w).length);
        Global.logger.d('  - [${w.wordId}] todayTimes=${w.todayLearnedTimes}, isMastered=$isMastered, isFinished=$isFinished');
      }

      // 在当前批次内，推导当前单词和环节
      List<LearningWord> sortedBatchWords = List.from(batchWords);
      sortedBatchWords.sort((a, b) {
        // 状态驱动：已掌握单词视为已完成今日所有环节
        final bool isAFinished = a.isEffectivelyMastered(masteredWordIds);
        final bool isBFinished = b.isEffectivelyMastered(masteredWordIds);

        final int trackLenA = trackOf(a).length;
        final int trackLenB = trackOf(b).length;
        final int effA = isAFinished ? trackLenA : min(a.todayLearnedTimes, trackLenA);
        final int effB = isBFinished ? trackLenB : min(b.todayLearnedTimes, trackLenB);

        // 优先练习今日学习次数较少的单词
        if (effA != effB) {
          return effA.compareTo(effB);
        }
        // 次数相同时，严格按照既定学习序号排序，确保“从左到右”的直观体验
        return a.learningOrder.compareTo(b.learningOrder);
      });

      final currentWordForPos = sortedBatchWords.first;
      int currentWordIndex = todayWords.indexOf(currentWordForPos);

      // 获取当前学习环节：由该单词今日已练习的次数在自身轨道内推导
      // 状态驱动：已掌握单词直接视为处于最后一个环节或已越过
      final bool currentWordFinished = currentWordForPos.isEffectivelyMastered(masteredWordIds);
      final List<String> currentTrack = trackOf(currentWordForPos);
      int currentStepIndex = currentWordFinished ? currentTrack.length : currentWordForPos.todayLearnedTimes;
      if (currentStepIndex >= currentTrack.length) {
        currentStepIndex = currentTrack.length - 1;
      }

      // 仅在推进进度或提供评分时更新当前单词状态
      // fsrsRating != null 或 isWordMastered = true 时，说明用户已经完成了一次对该词的有效评价，需要保存
      bool shouldSave = gotoNext || fsrsRating != null || isWordMastered;
      if (shouldSave) {
        final currWord = todayWords[currentWordIndex];
        final bool isReviewWord = StudyTrack.isReviewTrack(
              stability: currWord.stability,
              state: currWord.state,
              lastLearningDate: currWord.lastLearningDate,
              todayFirstLogElapsedDays: firstLogs[currWord.wordId]?.elapsedDays,
              today: today,
            );
        // 本次评分后接续的组：测评环节（首条评分）时按答对/答错选组；
        // 其余环节轨道已完整（首条评分后轨道扩展），无接续组
        List<String>? groupAfterRating;
        if (currentStepIndex == 0 && fsrsRating != null) {
          groupAfterRating = fsrsRating == FsrsRating.again
              ? (isReviewWord ? reviewCfg.wrong : newCfg.wrong)
              : (isReviewWord ? reviewCfg.correct : newCfg.correct);
        }
        // allStepsCompletedForWord: 本次评分提交后，该词是否还有剩余评分环节。
        // 测评评分时轨道尚未按首条评分扩展，按所选组长度判定；其余环节轨道完整，
        // List 恒为末位且不评分。updateCurrWord 用它决定 state：无剩余评分环节才转 review/relearning
        final bool allStepsCompletedForWord = groupAfterRating != null
            ? groupAfterRating.isEmpty
            : !StudyTrack.hasMoreGradedSteps(currentTrack, currentStepIndex);
        final nextFsrsItem = await updateCurrWord(
          isWordMastered: isWordMastered,
          currWord: currWord,
          user: user,
          now: now,
          db: db,
          allStepsCompletedForWord: allStepsCompletedForWord,
          fsrsRating: fsrsRating,
        );
        // 刚写入的今日首条评分日志立即固化进轨道判定 Map（当日轨道不漂移）
        if (nextFsrsItem != null && fsrsRating != null) {
          firstLogs.putIfAbsent(currWord.wordId,
              () => (elapsedDays: nextFsrsItem.elapsedDays, rating: fsrsRating.value));
        }

        // 同步内存状态
        if (gotoNext) {
          if (isWordMastered) {
            masteredWordIds.add(currWord.wordId);
          }
        }
      }

      // 如果当前是列表模式，直接返回列表页面，不关心下一个单词逻辑（因为是由 "CompleteList" 触发批量进度）
      bool isListStep = currentStepIndex < currentTrack.length && currentTrack[currentStepIndex] == 'List';
      if (isListStep) {
        Global.logger.d('当前为列表模式，显示批次单词列表');
        // 构建当前批次第一个单词的 LearningWordVo 以携带当前批次正确的 batchId
        final returnWord = todayWords[batchStartIndex];
        final userVo = UserVo.fromUser(user);
        final wordVo = WordVo.c2('')..id = returnWord.wordId;
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

        return Result<GetWordResult>("SUCCESS", "获取成功", true)
          ..data = GetWordResult(
            learningWordVo,
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
      int nextBatchStartIndex = _calculateBatchStartIndex(todayWords, masteredWordIds,
          firstLogs: firstLogs,
          newCfg: newCfg,
          reviewCfg: reviewCfg,
          batchSize: batchSize);
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
        final bool isAFinished = a.isEffectivelyMastered(masteredWordIds);
        final bool isBFinished = b.isEffectivelyMastered(masteredWordIds);

        final int trackLenA = trackOf(a).length;
        final int trackLenB = trackOf(b).length;
        final int effA = isAFinished ? trackLenA : min(a.todayLearnedTimes, trackLenA);
        final int effB = isBFinished ? trackLenB : min(b.todayLearnedTimes, trackLenB);

        if (effA != effB) {
          return effA.compareTo(effB);
        }
        // 次数相同时，严格按照既定学习序号排序
        return a.learningOrder.compareTo(b.learningOrder);
      });

      final nextWordForPos = nextBatchWords.first;
      int nextWordIndex = todayWords.indexOf(nextWordForPos);

      // 计算下一个单词应该展示的学习环节（在自身轨道内推导）
      final bool nextWordFinished = nextWordForPos.isEffectivelyMastered(masteredWordIds);
      final List<String> nextTrack = trackOf(nextWordForPos);
      int nextStepIndex = nextWordFinished ? nextTrack.length : nextWordForPos.todayLearnedTimes;
      if (nextStepIndex >= nextTrack.length) {
        nextStepIndex = nextTrack.length - 1;
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
      final otherWords = await getTwoOtherWords(nextTrack, nextStepIndex, targetMeaningItemVos, todayWords, returnWord, db);
      Global.logger.d('🐛 [BDC Performance Item] 加载混淆项耗时: ${swDistractor.elapsedMilliseconds} ms');

      // 计算学习进度
      // 状态驱动：每个单词按其自身轨道的环节数贡献进度（复习词轨道更短）

      // 计算所有单词的今日已学习次数总和
      int totalCompletedSteps = 0;
      int totalSteps = 0;
      for (final word in todayWords) {
        final int trackLen = trackOf(word).length;
        totalCompletedSteps += word.getCompletedSteps(masteredWordIds, trackLen);
        totalSteps += trackLen;
      }

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
          returnWord.isEffectivelyMastered(masteredWordIds), // wordMastered
        );

      Global.logger.d('🐛 [BDC Performance Item] getWord 内部计算总耗时: ${swTotal.elapsedMilliseconds} ms');
      return result;
    } catch (e, stackTrace) {
      Global.logger.e('获取下一个单词失败 [StudyBo]: $e', stackTrace: stackTrace);
      rethrow; // 直接抛出异常，不再包装成 Result，保留完整堆栈
    }
  }

  /// 更新当前单词的学习进度与 FSRS 状态；返回本次计算出的 FSRSItem（无评分时 null）
  Future<FSRSItem?> updateCurrWord({
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
      return null;
    }

    if (fsrsRating == FsrsRating.again) {
      // 若评分是 Again (答错), 则保存错词
      await saveWrongWord(currWord, db, user, now);
    }

    // FSRS 逻辑：学习事件（当天重设）与复习事件（跨天单次信号）区分
    // - 新词首次评分（stability 空/0）：init
    // - 当天非首次评分（学习轨道巩固 / 复习轨道重测）：relearn 重设（可升可降）
    // - 跨天首次评分（复习词测评 / 学一半词次日检验）：next 复习公式
    FSRSItem? nextFsrs;
    if (fsrsRating != null) {
      final fsrs = FSRS();
      if (currWord.stability == null || currWord.stability == 0.0) {
        if (currWord.stability == 0.0) {
           Global.logger.w('发现存量数据 stability 为 0.0, wordId: ${currWord.wordId}, 将视同新词执行 init');
        }
        // 新词首次评分；若已是当天最后一个评分环节，直接转 review/relearning，
        // 与 relearn 分支的 state 判据对称（防止学完的词次日被"学一半"判定误抓）
        nextFsrs = fsrs.init(fsrsRating,
            nextState: allStepsCompletedForWord
                ? (fsrsRating == FsrsRating.again ? FsrsState.relearning : FsrsState.review)
                : FsrsState.learning);
      } else {
        final currentFsrs = FSRSItem(
          stability: currWord.stability!,
          difficulty: currWord.difficulty!,
          elapsedDays: currWord.elapsedDays!,
          scheduledDays: currWord.scheduledDays!,
          reps: currWord.reps!,
          lapses: currWord.lapses!,
          state: FsrsStateExt.fromInt(currWord.state),
        );
        // 判定当天首次 vs 当天非首次（业务日比较；跨天重置保留 lastLearningDate，判定可靠）
        final bool isSameDayToday = currWord.lastLearningDate != null &&
            DateUtils.isSameBusinessDay(currWord.lastLearningDate!, AppClock.today());
        if (isSameDayToday) {
          // 学习/重测事件：重设稳定性与难度。state 判据：本次提交后是否还有评分环节
          //（评分环节 = 轨道中 List 之外的环节；List 恒为末位且不评分，
          //  故 allStepsCompletedForWord 语义为"最后一个评分环节已提交"，见 getWord）。
          nextFsrs = fsrs.relearn(currentFsrs, fsrsRating,
              nextState: allStepsCompletedForWord
                  ? (fsrsRating == FsrsRating.again ? FsrsState.relearning : FsrsState.review)
                  : FsrsState.learning);
        } else {
          // 复习事件：每天一次的复习信号
          int elapsedDays = 0;
          if (currWord.lastLearningDate != null) {
            final lastDate = DateUtils.businessDate(currWord.lastLearningDate!);
            final todayDate = AppClock.today();
            elapsedDays = todayDate.difference(lastDate).inDays;
          }
          nextFsrs = fsrs.next(currentFsrs, fsrsRating, elapsedDays);
        }
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
      return null;
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
      todayLearnedTimes: (currWord.todayLearnedTimes) + 1,
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
    return nextFsrs;
  }

  /// 查询今日单词在今天的首条评分日志的 elapsedDays（用于固化当天学习/复习轨道）
  Future<Map<String, ({int elapsedDays, int rating})>> _loadTodayFirstLogs(
      String userId, List<LearningWord> words) async {
    final result = <String, ({int elapsedDays, int rating})>{};
    if (words.isEmpty) return result;
    final db = MyDatabase.instance;
    final todayStart = AppClock.today();
    final rows = await (db.select(db.learningLogs)
          ..where((l) =>
              l.userId.equals(userId) &
              l.wordId.isIn(words.map((w) => w.wordId)) &
              l.createTime.isBiggerOrEqualValue(todayStart)))
        .get();
    // 每词取最早一条日志（今天首条评分）的 elapsedDays 与 rating（用于固化轨道与扩展复习轨道）
    final earliestTime = <String, DateTime>{};
    for (final row in rows) {
      final prev = earliestTime[row.wordId];
      if (prev == null || row.createTime.isBefore(prev)) {
        earliestTime[row.wordId] = row.createTime;
        result[row.wordId] = (elapsedDays: row.elapsedDays, rating: row.rating);
      }
    }
    return result;
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

  Future<List<WordVo>> getTwoOtherWords(List<String> trackSteps, int learningMode, List<MeaningItemVo> meaningItemVos,
      List<LearningWord> todayWords, LearningWord targetWordLearningData, MyDatabase db) async {
    final config = StudyConfig.fromCurrentUser();
    final strategy = DistractorStrategyFactory.getStrategy(config.distractorStrategy);
    return await strategy.getTwoOtherWords(
      trackSteps: trackSteps,
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
  /// 逻辑：找到第一个今日尚未完成所有轨道环节的批次（每词按其自身轨道长度判定）
  static int _calculateBatchStartIndex(List<LearningWord> todayWords, Set<String> masteredWordIds,
      {required Map<String, ({int elapsedDays, int rating})> firstLogs,
      required ThreeGroupSteps newCfg,
      required ThreeGroupSteps reviewCfg,
      int batchSize = 10}) {
    final today = AppClock.today();
    for (int i = 0; i < todayWords.length; i += batchSize) {
      bool batchFinished = true;
      for (int j = i; j < i + batchSize && j < todayWords.length; j++) {
        // 状态驱动：如果单词已学完（达到毕业稳定性，或者在 masteredWords 表中存在，或者今日学习次数已走完自身轨道）
        final first = firstLogs[todayWords[j].wordId];
        final trackLen = StudyTrack.trackOf(
          stability: todayWords[j].stability,
          state: todayWords[j].state,
          lastLearningDate: todayWords[j].lastLearningDate,
          todayFirstLogElapsedDays: first?.elapsedDays,
          todayFirstLogRating: first?.rating,
          newCheck: newCfg.check,
          newCorrect: newCfg.correct,
          newWrong: newCfg.wrong,
          reviewCheck: reviewCfg.check,
          reviewCorrect: reviewCfg.correct,
          reviewWrong: reviewCfg.wrong,
          today: today,
        ).length;
        bool wordFinished = todayWords[j].isTodayFinished(masteredWordIds, trackLen);
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



  /// 将指定单词标记为已掌握（用于回看模式等特殊场景下直接保存）
  Future<void> markWordAsMastered(LearningWordVo learningWordVo) async {
    final db = MyDatabase.instance;
    final user = Global.getLoggedInUser();
    if (user == null) return;

    final lwQuery = db.select(db.learningWords)
      ..where((tbl) => tbl.wordId.equals(learningWordVo.word.id!) & tbl.userId.equals(user.id));
    final lwList = await lwQuery.get();
    if (lwList.isEmpty) return;
    final lw = lwList.first;

    await _saveMasteredWord(
      learningWord: lw,
      user: user,
      now: AppClock.now(),
      db: db,
    );
  }


  Future<void> _saveMasteredWord({
    required LearningWord learningWord,
    required User user,
    required DateTime now,
    required MyDatabase db,
  }) async {
    // 学习轨道长度（三组结构：测评 + 答对组 + List）用于饱和填充今日环节数
    final newCfg = await _studyStepsService.getThreeGroupConfig('new');
    final int stepCount = newCfg.correct.length + 2;

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
