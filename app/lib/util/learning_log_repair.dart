import 'package:drift/drift.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/date_utils.dart';
import 'package:nnbdc/util/db_log_util.dart';
import 'package:nnbdc/util/prefs.dart';

/// 客户端一次性数据修复：清理"同一次作答被重复计分"产生的 learning_logs 脏数据。
///
/// 背景：旧客户端会把一次作答提交两次（autoJump 定时器 / 详情页 / 下一词按钮多链路），
/// 第二次被误判成"下一个环节的首次作答"，于是同一 (user_id, word_id) 多写了一条日志，
/// 并把该词 learning_words 的 stability/difficulty/elapsed_days/scheduled_days 覆盖成
/// 错误值（旧代码走同日 relearn 会把它打回初始值，例如 5.8/2.4/0.4）。
/// 闸门修复见 bdc_notifier 的 _pendingGrade/_answerAccepted，本类只修存量，不产生新脏数据。
///
/// 判据（已与服务端 pg_dump 副本上的验证一致）：同一 (user_id, word_id) 的日志按时间排序，
/// 与前一条间隔 < 50ms 的即为重复 → 删除它（成簇时保留簇首，即最早那条）。
/// 依据：线上间隔直方图呈明显双峰（10~50ms 聚集 11.3 万条，0.2s~5s 几乎为空），
/// 人不可能在 50ms 内答完下一题。
///
/// 一次性修复要完整：删除重复日志只是第一步，同一次重复作答**已经派生出去的计数**
/// 必须一起回滚（user_study_daily_stats.review_count、learning_words.learnedTimes/
/// todayLearnedTimes），否则打卡率与学习进度会永久虚高；同时每条删除都要写最小化的
/// DELETE 同步日志，让其他设备收敛（见 [sync.dart] 的 learningLogs DELETE 分支）。
///
/// 注意：drift 的 DateTime 列在本地 SQLite 中默认存 Unix 秒，因此毫秒级重复的两条日志
/// 绝大多数会落在同一秒（本判据在本地退化为"同秒即重复"），只有跨越秒边界的那一小部分
/// 无法在本地识别（服务端 create_time 来自同步日志里的 ISO 时间戳，精度是毫秒）。
/// 同一秒内也无法用 id（Util.uuid() 是随机 UUIDv4，无时序语义）区分先后，
/// 必须借助 SQLite 隐式 rowid（严格按写入顺序递增）才能稳定保留"最早那条"。
class LearningLogRepair {
  LearningLogRepair._();

  /// 相邻两条日志被视为"同一次作答重复计分"的最大间隔。
  static const Duration duplicateInterval = Duration(milliseconds: 50);

  /// 单次运行最多删除的重复日志条数。
  ///
  /// 同步不分页、单次 POST，服务端 nginx client_max_body_size 限制 5MB；若一次删除量过大
  /// （单设备约 2 万条），DELETE 日志会把同步请求撑爆（413/超时），失败后本地 user_db_logs
  /// 队列永不排空，该用户所有表都同步不了。因此限额分批，剩余部分靠幂等断点续传。
  static const int maxDeletionsPerRun = 5000;

  /// 待续跑标记：本次因达到 [maxDeletionsPerRun] 提前结束时置位，下次启动再清一轮。
  static const String pendingPrefsKey = 'learningLogRepairPending';

  /// 修复全部用户的重复计分脏数据（幂等：重复执行不会再删行、不会再改值）。
  ///
  /// 整体放在一个事务里，避免中途失败留下"日志删了但 learning_words 没回填"的半成品。
  /// [limit] 为单次删除上限（用于分批限流）；达到上限时返回的 `completed` 为 false，
  /// 调用方应置 [pendingPrefsKey] 标记并在后续启动续跑。
  static Future<({int deletedLogs, int affectedWords, bool completed})>
      repairDuplicateLearningLogs(MyDatabase db,
          {int limit = maxDeletionsPerRun}) async {
    var deletedLogs = 0;
    var affectedWords = 0;
    var completed = true;

    await db.transaction(() async {
      // 跨用户扫表：迁移期没有"当前登录用户"，userId 一律取自每行的 user_id
      final rows = await (db.selectOnly(db.learningLogs, distinct: true)
            ..addColumns([db.learningLogs.userId]))
          .get();

      for (final row in rows) {
        final userId = row.read(db.learningLogs.userId)!;
        final remaining = limit - deletedLogs;
        if (remaining <= 0) {
          completed = false;
          break;
        }
        final result = await _repairUser(db, userId, limit: remaining);
        deletedLogs += result.deletedLogs;
        affectedWords += result.affectedWords;
        if (result.limitReached) {
          completed = false;
          break;
        }
      }
    });

    Global.logger.i(
        '🧹 [LearningLogRepair] 重复计分修复${completed ? '完成' : '暂告一段落(达到单次上限，待续跑)'}: '
        '删除 $deletedLogs 条重复日志, 受影响 $affectedWords 个词');
    // 未清完则置待续跑标记，后续启动继续清（已删的不再匹配，天然断点续传）；清完则清标记
    await Prefs.write(pendingPrefsKey, !completed);
    return (deletedLogs: deletedLogs, affectedWords: affectedWords, completed: completed);
  }

  /// App 启动时的续跑钩子：上一次因达到单次上限未清完时，再跑一轮直到清完。
  ///
  /// 放在启动钩子而非每次启动无条件跑，是为了避免为绝大多数用户白白扫一遍日志表。
  static Future<void> resumePendingIfNeeded() async {
    if (Prefs.read<bool>(pendingPrefsKey) != true) return;
    try {
      await repairDuplicateLearningLogs(MyDatabase.instance);
    } catch (e, stackTrace) {
      // 失败保留标记，下次启动重试（修复幂等，已删的不再匹配）
      Global.logger.e('🧹 [LearningLogRepair] 续跑失败，保留标记待下次启动重试: $e',
          error: e, stackTrace: stackTrace);
    }
  }

  /// 修复单个用户，返回 (删除的重复日志数, 受影响的词数, 是否触达单次上限)。
  static Future<({int deletedLogs, int affectedWords, bool limitReached})>
      _repairUser(
    MyDatabase db,
    String userId, {
    required int limit,
  }) async {
    // 按 (wordId, createTime, rowid) 排序：rowid 是本地秒级时间精度下唯一可靠的写入顺序
    final logs = await (db.select(db.learningLogs)
          ..where((l) => l.userId.equals(userId))
          ..orderBy([
            (l) => OrderingTerm(expression: l.wordId),
            (l) => OrderingTerm(expression: l.createTime),
            (l) => OrderingTerm(expression: CustomExpression<int>('rowid')),
          ]))
        .get();

    final duplicates = <LearningLog>[];
    // wordId -> 去重后现存最后一条日志，用于回填 learning_words
    final lastSurvivors = <String, LearningLog>{};
    // 每个词被删掉的重复条数（用于回滚 learnedTimes/todayLearnedTimes）
    final deletedPerWord = <String, int>{};
    // 业务日 -> 被删掉的重复条数（用于回滚 review_count）
    final deletedPerDay = <DateTime, int>{};

    String? currentWordId;
    LearningLog? previous;
    var limitReached = false;
    for (final log in logs) {
      if (log.wordId != currentWordId) {
        currentWordId = log.wordId;
        previous = null;
      }

      final isDuplicate =
          previous != null && log.createTime.difference(previous.createTime) < duplicateInterval;
      if (isDuplicate) {
        if (duplicates.length >= limit) {
          // 达到单次上限：停止识别，本次不再继续删；剩余重复项下次启动靠幂等继续命中
          limitReached = true;
          break;
        }
        duplicates.add(log);
        deletedPerWord[log.wordId] = (deletedPerWord[log.wordId] ?? 0) + 1;
        final businessDay = DateUtils.businessDate(log.createTime);
        deletedPerDay[businessDay] = (deletedPerDay[businessDay] ?? 0) + 1;
      } else {
        lastSurvivors[log.wordId] = log;
      }
      // 判据是"与前一条的间隔"，因此无论当前条是否重复，都要成为下一条的比较基准
      previous = log;
    }

    if (duplicates.isEmpty) {
      return (deletedLogs: 0, affectedWords: 0, limitReached: limitReached);
    }

    // 1) 删除重复日志，并为每条删除写 learningLogs 的 DELETE 同步日志（客户端上报后服务端自动收敛）。
    //    DELETE 只需 id 定位目标，record 最小化为 {'id': ...}：完整实体约 250B，量大时会把
    //    单次同步 POST 撑过 nginx client_max_body_size(5m)。服务端 DELETE 分支只用 id 构造实体后按 id 删。
    for (final duplicate in duplicates) {
      await (db.delete(db.learningLogs)..where((l) => l.id.equals(duplicate.id))).go();
      await DbLogUtil.logOperation(
          duplicate.userId, 'DELETE', 'learningLogs', duplicate.id, {'id': duplicate.id});
    }

    // 2) 回滚被删重复日志派生的每日评分次数（下限 0；按业务日 03:00 口径归集）
    for (final entry in deletedPerDay.entries) {
      await db.userStudyDailyStatsDao.decrementReviewCount(
        userId,
        entry.key,
        count: entry.value,
      );
    }

    // 3) 用现存最后一条日志回填被污染的记忆字段，并回滚该词虚增的学习次数；已掌握词只回滚计数
    final masteredWordIds = await db.masteredWordsDao.getMasteredWordIdSet(userId);
    for (final entry in lastSurvivors.entries) {
      final learningWord = await db.learningWordsDao.getById(userId, entry.key);
      if (learningWord == null) {
        continue;
      }

      // 已掌握词不回填：掌握 = 该词已进入「已掌握」词书（唯一口径），
      // 掌握是用户可见、可编辑的事实，其 stability 历史上可能是毕业哨兵值（180.0 或 120.0），
      // 不代表真实记忆强度，不能按日志改回去。
      // 不拿 stability >= 掌握线当判据：那是代理判据，会把"稳定度恰好越过掌握线、
      // 但并未进入已掌握词书"的词误判成已掌握而漏回填。
      final isMastered = masteredWordIds.contains(learningWord.wordId);

      final removed = deletedPerWord[entry.key] ?? 0;
      var restored = learningWord;
      if (!isMastered) {
        final lastLog = entry.value;
        restored = restored.copyWith(
          stability: Value(lastLog.stability),
          difficulty: Value(lastLog.difficulty),
          elapsedDays: Value(lastLog.elapsedDays),
          scheduledDays: Value(lastLog.scheduledDays),
        );
      }
      if (removed > 0) {
        final learnedTimes = restored.learnedTimes - removed;
        final todayLearnedTimes = restored.todayLearnedTimes - removed;
        restored = restored.copyWith(
          learnedTimes: learnedTimes < 0 ? 0 : learnedTimes,
          todayLearnedTimes: todayLearnedTimes < 0 ? 0 : todayLearnedTimes,
        );
      }

      // saveEntity 仅在值真正变化时落库，并以复合主键 userId-wordId 写 learningWords 的 UPDATE 同步日志
      await db.learningWordsDao.saveEntity(restored, true);
    }

    return (deletedLogs: duplicates.length, affectedWords: lastSurvivors.length, limitReached: limitReached);
  }
}
