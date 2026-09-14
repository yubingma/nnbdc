import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/util/distractor_strategy.dart';
import 'package:nnbdc/util/study_track.dart';
import 'package:nnbdc/util/study_config.dart';
import 'package:nnbdc/util/study_steps_service.dart';
import 'package:nnbdc/util/learning_service.dart';
import 'package:nnbdc/services/user_privilege_manager.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/db/learning_word_extensions.dart';
import 'package:nnbdc/db/user_extensions.dart';
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
import 'package:nnbdc/util/study_audio_session_controller.dart';

/// 学习批次区间模型
class BatchRange {
  final int startIndex;
  final int length;
  final int groupNo; // 1-based 序号，即「第 N 组」

  const BatchRange({
    required this.startIndex,
    required this.length,
    required this.groupNo,
  });

  int get endIndex => startIndex + length;

  bool containsIndex(int index) => index >= startIndex && index < endIndex;
}

/// 业务对象（BO）：承载本地实现逻辑
class StudyBo {
  /// 学习批次大小（每组单词数）：用户在「高级学习设置」中配置，
  /// 且不超过当日计划词数（见 [StudyConfig.effectiveBatchSize]）。
  /// 与 getWord / calculateBatches 的批次划分保持一致。
  /// 调用方取一次到局部变量复用：每次访问都会重新解析一遍 studyConfig。
  static int get batchSize => StudyConfig.fromCurrentUser()
      .effectiveBatchSize(Global.getLoggedInUser()?.effectiveWordsPerDay ?? 0);

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


  /// 加量：打卡后额外追加一组单词（词数 = 当前生效的每组单词数）。
  ///
  /// 加量是会员权益，且**不计入"今日计划"**：它只是追加一个新的取词批次
  /// （复用语料配额与排序逻辑，等价于"当初把今日计划设为 已选词数 + count 时的最后 count 个词"）。
  /// 学习页按 batchId 顺序自动续学，因此中途退出后重新进入可继续未完成的加量批次。
  ///
  /// [count] 缺省为一组；返回 [Result.data] 为本次实际追加的词数。
  Future<Result<int>> prepareExtraStudy({int? count}) async {
    try {
      final user = Global.getLoggedInUser();
      if (user == null) {
        Global.logger.e('加量失败：用户未登录');
        return Result("ERROR", "用户未登录", false);
      }

      if (!UserPrivilegeManager.canExtraStudy) {
        Global.logger.i('加量被拒：无加量权限');
        return Result("NO_PREMIUM", "加量是会员专属权益", false);
      }

      final todayWords = await LearningService.getTodayLearningWordsFromDb(user.id);
      if (todayWords.isEmpty) {
        return Result("ERROR", "请先完成今日学习", false);
      }

      final int extraCount = count ?? batchSize;

      // genTodayWords 会就地向传入列表追加并返回同一实例，故先记录追加前的词数
      final int beforeCount = todayWords.length;
      final targetTotal = beforeCount + extraCount;

      Global.logger.d('开始加量：当前今日词数=$beforeCount, 本次追加=$extraCount, 目标总数=$targetTotal');
      final allWords = await LearningService.genTodayWords(
        user.id,
        AppClock.now(),
        todayWords,
        minNewWordsPerDay: StudyConfig.fromCurrentUser().minNewWordsPerDay,
        targetTotalWords: targetTotal,
        isExtra: true,
      );

      final int addedCount = allWords.length - beforeCount;
      if (addedCount <= 0) {
        Global.logger.w('加量未取到新词：词书已无可学单词');
        return Result("NNBDC-0012", "词书已没有更多单词可供加量", false);
      }

      await LearningService.updateTodayLearningWords(allWords, AppClock.now());
      StudyCacheManager().clear();
      // 今日学习列表已追加新的加量批次：在事实源头广播，让今日计划页刷新加量进度与主按钮。
      // 不能只依赖计划页 push('/bdc') 的 .then：学习页跳完成页用 pushReplacement，
      // 被替换路由的 future 永不完成，从完成页发起的加量回到计划页时会停在旧快照。
      EventBus.publishTodayStudyListChanged(const TodayStudyListChangedEvent());
      ThrottledDbSyncService().requestSync(immediate: true);
      Global.logger.d('加量完成：已追加 $addedCount 个单词');

      return Result("SUCCESS", "已追加 $addedCount 个单词", true)..data = addedCount;
    } catch (e, stackTrace) {
      Global.logger.e('加量失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "加量失败: ${e.toString()}", false);
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

      // 状态驱动：推导当前批次 (BatchRange)
      final firstLogs =
          await _loadTodayFirstLogs(user.id, todayWords);
      final int batchSize = StudyBo.batchSize;
      final currentBatch = calculateCurrentBatch(todayWords, masteredWordIds,
          firstLogs: firstLogs,
          newCfg: newCfg,
          reviewCfg: reviewCfg,
          batchSize: batchSize);
      if (currentBatch == null) {
        Global.logger.d('所有批次单词已完成');
        return [];
      }

      // 获取当前批次的单词
      final batchWords = todayWords.sublist(currentBatch.startIndex, currentBatch.endIndex);

      Global.logger.d('获取到批次单词数量: ${batchWords.length}, 批次起始索引: ${currentBatch.startIndex}, 第${currentBatch.groupNo}组');

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
      final isFirstDakaToday = existingDaka == null;
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

      // 打卡统计（累计天数/连续天数/打卡率）是 `dakas` 表的派生量，绝不做 `+1` 增量累加——
      // 增量累加基于可能过期的缓存值，多端必然互相漂移。统一交由下方幂等的推导方法，从本机 `dakas` 表重算。
      await UserBo().updateAndSyncUserDakaStats(user.id);

      // 每日首次打卡：赠送一次掷骰子机会（在推导之后再写，确保携带的是修正后的正确统计值）
      if (isFirstDakaToday) {
        final refreshed = Global.getLoggedInUser();
        if (refreshed != null) {
          await db.usersDao.saveUser(
              refreshed.copyWith(throwDiceChance: refreshed.throwDiceChance + 1),
              true);
        }
      }

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

      // 计算当前批次 (BatchRange)
      final firstLogs =
          await _loadTodayFirstLogs(user.id, todayWords);
      final int batchSize = StudyBo.batchSize;
      final currentBatch = calculateCurrentBatch(todayWords, masteredWordIds,
          firstLogs: firstLogs,
          newCfg: newCfg,
          reviewCfg: reviewCfg,
          batchSize: batchSize);
      if (currentBatch == null) {
        return Result("ERROR", "所有单词已完成列表学习", false);
      }

      // 获取当前 batch words
      final batchWords = todayWords.sublist(currentBatch.startIndex, currentBatch.endIndex);

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
        // 空计划绝不能一概当成"今日已完成"去打卡：跨天重置尚未执行时（用户最近学习日早于今天），
        // 空计划只说明本日计划还没就绪（重置刚清零、取词尚未落库），必须回今日计划页重新准备。
        final bool crossDayPending = lastDate == null || lastDate.isBefore(today);
        if (crossDayPending) {
          Global.logger.w('🛑 [StudyBo-DateCheck] 今日计划为空且跨天重置尚未执行，终止学习流程！');
          return Result<GetWordResult>("NEW_DAY", "已进入新的一天，请重新开始学习", false);
        }
        return _buildTodayStudyFinishedResult();
      }

      // 跨天残留防线：计划里的"今日进度"必须属于本日计划所属的业务日。若残留着更早的进度，
      // 说明本日计划尚未跨天重置，此时"所有词都走完了轨道"只是昨日残留造成的假象，
      // 绝不能让学习页据此判定今日已完成并把人送去打卡页。
      final DateTime planDay = currentUser.lastLearningDate != null
          ? DateUtils.businessDate(currentUser.lastLearningDate!)
          : today;
      if (todayWords.any((w) => w.hasTodayProgressBefore(planDay))) {
        Global.logger.w('🛑 [StudyBo-DateCheck] 检测到跨天残留的今日进度，本日计划尚未重置，终止学习流程！');
        return Result<GetWordResult>("NEW_DAY", "已进入新的一天，请重新开始学习", false);
      }
      Global.logger.d('🐛 [BDC Performance Item] 查询今日单词列表耗时: ${swWords.elapsedMilliseconds} ms');

      final swMastered = Stopwatch()..start();
      final masteredWordIds = await StudyCacheManager().getMasteredWordIds(db, user.id);
      Global.logger.d('🐛 [BDC Performance Item] 查询已掌握单词ID耗时: ${swMastered.elapsedMilliseconds} ms');

      // 查询今天首条评分日志（间隔+评分）：固化每个词的当天轨道（学习/复习），当天不漂移
      final firstLogs =
          await _loadTodayFirstLogs(user.id, todayWords);
      // 旧词三组显式规则（未设置时轨道层回退默认）

      // 状态驱动：推导当前批次 (BatchRange)
      final int batchSize = StudyBo.batchSize;
      final currentBatch = calculateCurrentBatch(todayWords, masteredWordIds,
          firstLogs: firstLogs,
          newCfg: newCfg,
          reviewCfg: reviewCfg,
          batchSize: batchSize);
      if (currentBatch == null) {
        return _buildTodayStudyFinishedResult();
      }

      // 获取当前批次的单词
      final batchWords = todayWords.sublist(currentBatch.startIndex, currentBatch.endIndex);

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
      Global.logger.d('~~~~~BDC_BATCH: startIdx=${currentBatch.startIndex}, batchSize=${batchWords.length}');
      for (var w in batchWords) {
        final bool isMastered = w.isEffectivelyMastered(masteredWordIds);
        final bool isFinished = w.isTodayFinished(masteredWordIds, trackOf(w).length);
        Global.logger.d('  - [${w.wordId}] todayTimes=${w.todayLearnedTimes}, isMastered=$isMastered, isFinished=$isFinished');
      }

      // 在当前批次内，推导当前单词和环节（练习题优先，List在后）
      List<LearningWord> sortedBatchWords = List.from(batchWords);
      sortedBatchWords.sort((a, b) => _compareBatchWords(
            a,
            b,
            masteredWordIds: masteredWordIds,
            trackOf: trackOf,
          ));

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
        final returnWord = todayWords[currentBatch.startIndex];
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

        final returnTrack = trackOf(returnWord);
        final listStepIndex = returnTrack.isNotEmpty ? returnTrack.length - 1 : 0;

        return Result<GetWordResult>("SUCCESS", "获取成功", true)
          ..data = GetWordResult(
            learningWordVo,
            listStepIndex,
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
      final nextBatch = calculateCurrentBatch(todayWords, masteredWordIds,
          firstLogs: firstLogs,
          newCfg: newCfg,
          reviewCfg: reviewCfg,
          batchSize: batchSize);
      if (nextBatch == null) {
        return _buildTodayStudyFinishedResult();
      }

      // 获取下一个单词所在的批次
      final nextBatchWords = todayWords.sublist(nextBatch.startIndex, nextBatch.endIndex);

      // 按照优先级排序，找出该批次最需要学习的下一个单词（练习题优先，List在后）
      nextBatchWords.sort((a, b) => _compareBatchWords(
            a,
            b,
            masteredWordIds: masteredWordIds,
            trackOf: trackOf,
          ));

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

  /// 今天测评答错（当天**首条**评分为 again）的词 id 集合。
  /// 与轨道名「新词答错 / 旧词答错」同一判据（不是"今天任何一次答错"），
  /// 供本组小结把答错的词标红。
  Future<Set<String>> getTodayWrongWordIds(Iterable<String> wordIds) async {
    final user = Global.getLoggedInUser();
    if (user == null) return {};
    final logs = await _loadTodayFirstLogsOfIds(user.id, wordIds);
    return {
      for (final e in logs.entries)
        if (e.value.rating == FsrsRating.again.value) e.key,
    };
  }

  /// 查询今日单词在今天的首条评分日志的 elapsedDays（用于固化当天学习/复习轨道）
  Future<Map<String, ({int elapsedDays, int rating})>> _loadTodayFirstLogs(
          String userId, List<LearningWord> words) =>
      _loadTodayFirstLogsOfIds(userId, words.map((w) => w.wordId));

  Future<Map<String, ({int elapsedDays, int rating})>> _loadTodayFirstLogsOfIds(
      String userId, Iterable<String> wordIds) async {
    final result = <String, ({int elapsedDays, int rating})>{};
    final ids = wordIds.toList();
    if (ids.isEmpty) return result;
    final db = MyDatabase.instance;
    final todayStart = AppClock.today();
    final rows = await (db.select(db.learningLogs)
          ..where((l) =>
              l.userId.equals(userId) &
              l.wordId.isIn(ids) &
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

  /// 计算所有学习批次：严格按 batchId 边界对齐分块，并在同 batchId 内部按 batchSize 切片。
  /// 绝对禁止跨越 batchId 合并批次（防止计划词与加量词混合或短批次后移导致多出碎片批次）。
  static List<BatchRange> calculateBatches(List<LearningWord> todayWords, int batchSize) {
    if (todayWords.isEmpty) return const [];
    if (batchSize <= 0) batchSize = StudyBo.batchSize;

    final List<BatchRange> batches = [];
    int groupNo = 1;
    int i = 0;

    while (i < todayWords.length) {
      final currentBatchId = todayWords[i].batchId;
      // 找到同 batchId 的连续块终点
      int chunkEnd = i + 1;
      while (chunkEnd < todayWords.length && todayWords[chunkEnd].batchId == currentBatchId) {
        chunkEnd++;
      }

      // 在该 chunk 内部按 batchSize 切片
      for (int subStart = i; subStart < chunkEnd; subStart += batchSize) {
        final subLength = min(batchSize, chunkEnd - subStart);
        batches.add(BatchRange(
          startIndex: subStart,
          length: subLength,
          groupNo: groupNo++,
        ));
      }

      i = chunkEnd;
    }

    return batches;
  }

  /// 状态驱动：推导当前正在学习的批次 (BatchRange)
  /// 逻辑：找到第一个今日尚未完成所有轨道环节的批次（每词按其自身轨道长度判定）
  static BatchRange? calculateCurrentBatch(
    List<LearningWord> todayWords,
    Set<String> masteredWordIds, {
    required Map<String, ({int elapsedDays, int rating})> firstLogs,
    required ThreeGroupSteps newCfg,
    required ThreeGroupSteps reviewCfg,
    required int batchSize,
  }) {
    if (todayWords.isEmpty) return null;
    final batches = calculateBatches(todayWords, batchSize);
    final today = AppClock.today();

    for (final batch in batches) {
      bool batchFinished = true;
      for (int j = batch.startIndex; j < batch.endIndex; j++) {
        final word = todayWords[j];
        final first = firstLogs[word.wordId];
        final trackLen = StudyTrack.trackOf(
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
        ).length;
        final bool wordFinished = word.isTodayFinished(masteredWordIds, trackLen);
        if (!wordFinished) {
          batchFinished = false;
          break;
        }
      }
      if (!batchFinished) {
        return batch;
      }
    }
    return null; // 所有批次都学完了
  }

  /// 兼容/便捷接口：获取当前批次起始位置索引，学完返回 -1
  static int calculateBatchStartIndex(
    List<LearningWord> todayWords,
    Set<String> masteredWordIds, {
    required Map<String, ({int elapsedDays, int rating})> firstLogs,
    required ThreeGroupSteps newCfg,
    required ThreeGroupSteps reviewCfg,
    required int batchSize,
  }) {
    final currentBatch = calculateCurrentBatch(
      todayWords,
      masteredWordIds,
      firstLogs: firstLogs,
      newCfg: newCfg,
      reviewCfg: reviewCfg,
      batchSize: batchSize,
    );
    return currentBatch?.startIndex ?? -1;
  }

  /// 批次内单词调度排序比较器：
  /// 1. 已掌握或已完成所有轨道的单词排在最后；
  /// 2. 处于普通练习题（currentStep != 'List'）的单词严格优先于已到达 List 等待状态的单词；
  /// 3. 同处于普通练习题（或均处于 List）：按 todayLearnedTimes 升序（保证横向轮流推进）；
  /// 4. 步数相同时按批次内既定序号 learningOrder 升序（从左到右）。
  static int _compareBatchWords(
    LearningWord a,
    LearningWord b, {
    required Set<String> masteredWordIds,
    required List<String> Function(LearningWord) trackOf,
  }) {
    final trackA = trackOf(a);
    final trackB = trackOf(b);
    final bool isAFinished = a.isEffectivelyMastered(masteredWordIds) ||
        a.isTodayFinished(masteredWordIds, trackA.length);
    final bool isBFinished = b.isEffectivelyMastered(masteredWordIds) ||
        b.isTodayFinished(masteredWordIds, trackB.length);

    if (isAFinished != isBFinished) {
      return isAFinished ? 1 : -1;
    }
    if (isAFinished && isBFinished) {
      return a.learningOrder.compareTo(b.learningOrder);
    }

    final bool isAList = a.todayLearnedTimes < trackA.length &&
        trackA[a.todayLearnedTimes] == 'List';
    final bool isBList = b.todayLearnedTimes < trackB.length &&
        trackB[b.todayLearnedTimes] == 'List';

    // 普通练习题优先于 List 等待状态
    if (isAList != isBList) {
      return isAList ? 1 : -1;
    }

    if (a.todayLearnedTimes != b.todayLearnedTimes) {
      return a.todayLearnedTimes.compareTo(b.todayLearnedTimes);
    }
    return a.learningOrder.compareTo(b.learningOrder);
  }

  /// 学习页「第 N 组 · 轨道 · 环节 x/y」指示：[batchSize] 词一批，[groupNo] 为本组在今日
  /// 学习列表中的序号（1 起），[trackName] 为当前词所属的轨道名。
  ///
  /// x/y 是**当前词所在轨道**在本组本环节内的进度：一个环节常由多条轨道汇聚而来
  /// （如"新词答对 8 个 + 新词答错 2 个"都走汉译英），各条轨道分别计数 ——
  /// x 为该轨道内已走完本环节的词数 + 1，y 为该轨道内走本环节的词数
  /// （≠ 组内词数：已掌握的词、以及答对后不再走本环节的复习词都不计入）。
  /// 注意：这只影响指示器的显示口径，不参与任何调度 —— 出题顺序仍由
  /// _calculateBatchStartIndex / _compareBatchWords 决定（整组横向混排）。
  ///
  /// 无法定位（当前词不在本组、或该词今天不走这个环节）时返回 null。
  Future<({int position, int total, int groupNo, String trackName})?>
      getBatchPhaseProgress({
    required String wordId,
    required String step,
  }) async {
    final user = Global.getLoggedInUser();
    if (user == null) return null;
    final db = MyDatabase.instance;
    final todayWords = await StudyCacheManager().getTodayWords(db, user.id);
    final wordIndex = todayWords.indexWhere((w) => w.wordId == wordId);
    if (wordIndex < 0) return null;

    final int batchSize = StudyBo.batchSize;
    final batches = calculateBatches(todayWords, batchSize);
    final currentBatch = batches.firstWhere(
      (b) => b.containsIndex(wordIndex),
      orElse: () => BatchRange(startIndex: 0, length: todayWords.length, groupNo: 1),
    );
    final batchWords = todayWords.sublist(currentBatch.startIndex, currentBatch.endIndex);

    // 与 getWord 完全相同的轨道口径：今天首条评分日志固化当天轨道（新词/复习词、答对/答错组）
    final newCfg = await _studyStepsService.getThreeGroupConfig('new');
    final reviewCfg = await _studyStepsService.getThreeGroupConfig('review');
    final firstLogs = await _loadTodayFirstLogs(user.id, batchWords);
    final masteredWordIds = await StudyCacheManager().getMasteredWordIds(db, user.id);
    final today = AppClock.today();

    // 本组内走本环节的每个词 → (轨道环节序列, 是否旧词、今天首评, 已走完的环节数)
    final entries = <({
      String wordId,
      List<String> track,
      bool isReview,
      int? firstRating,
      int learnedTimes
    })>[];
    for (final word in batchWords) {
      // 已掌握的词不再出题，也不再占用本组名额
      if (word.isEffectivelyMastered(masteredWordIds)) continue;
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
        today: today,
      );
      // 该词今天不走这个环节（如复习词答对后没有 Ch2En），不计入本环节名额
      final stepIndexInTrack = track.indexOf(step);
      if (stepIndexInTrack < 0) continue;
      entries.add((
        wordId: word.wordId,
        track: track,
        isReview: StudyTrack.isReviewTrack(
          stability: word.stability,
          state: word.state,
          lastLearningDate: word.lastLearningDate,
          todayFirstLogElapsedDays: first?.elapsedDays,
          today: today,
        ),
        firstRating: first?.rating,
        learnedTimes: word.todayLearnedTimes,
      ));
    }

    final currentIndex = entries.indexWhere((e) => e.wordId == wordId);
    if (currentIndex < 0) return null;
    final current = entries[currentIndex];

    // 当前环节在轨道中的位置 = 该词今天已走完的环节数。
    // 不能用 track.indexOf(step)：当"答对组/答错组"里配了测评环节本身时，轨道会出现
    // 两次同名环节（如 [En2Ch, En2Ch, List]），indexOf 只会命中第一次，
    // 把第二遍英译汉误判成测评环节（轨道名错、分子还会超过分母）。
    final stepIndexInTrack = current.learnedTimes;
    if (stepIndexInTrack >= current.track.length ||
        current.track[stepIndexInTrack] != step) {
      return null;
    }
    // 同一阶段整组共用同一个"是否测评环节"判定；同轨道名的词轨道环节序列必然相同
    final isCheckStep = stepIndexInTrack == 0;
    String trackNameOf(
            ({String wordId, List<String> track, bool isReview, int? firstRating, int learnedTimes}) e) =>
        _trackNameOf(
          isReview: e.isReview,
          isCheckStep: isCheckStep,
          todayFirstLogRating: e.firstRating,
        );
    final currentTrackName = trackNameOf(current);
    final sameTrack = entries.where((e) => trackNameOf(e) == currentTrackName);
    final done =
        sameTrack.where((e) => e.learnedTimes > stepIndexInTrack).length;

    return (
      position: done + 1,
      total: sameTrack.length,
      groupNo: currentBatch.groupNo,
      trackName: currentTrackName,
    );
  }

  /// 单个词在某环节上的轨道名：[isCheckStep] 为真表示该环节就是这个词的测评环节
  /// （还没评分，只到「新词测评/旧词测评」），否则按今天首条评分分化为「答对/答错」。
  static String _trackNameOf({
    required bool isReview,
    required bool isCheckStep,
    required int? todayFirstLogRating,
  }) {
    final wordType = isReview ? '旧词' : '新词';
    if (isCheckStep) return '$wordType测评';
    return '$wordType${todayFirstLogRating == FsrsRating.again.value ? '答错' : '答对'}';
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

      // 学习中单词达到已掌握/毕业：播放泡泡回馈音效 (bubble-pop.wav)，给用户正向激励并便于运维感知
      StudyAudioSessionController.instance.playSoundEffect('bubble-pop.wav', speed: 1.0, volume: 0.8);
      Global.logger.i('🫧 [Mastered-Sound] 学习中单词 ${learningWord.wordId} 已掌握/毕业，触发泡泡回馈音效 (bubble-pop.wav)');
    } else {
      // 还在规划阶段：直接删除该学习记录
      await StudyCacheManager().deleteAndSyncWordState(db, learningWord);
    }

    // 将单词添加到已掌握词书
    await StudyCacheManager().saveMasteredWordAndSync(db, user.id, learningWord.wordId);

    ThrottledDbSyncService().requestSync();
  }
}
