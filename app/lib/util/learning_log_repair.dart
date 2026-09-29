import 'package:drift/drift.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/db_log_util.dart';

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
/// 注意：drift 的 DateTime 列在本地 SQLite 中默认存 Unix 秒，因此毫秒级重复的两条日志
/// 绝大多数会落在同一秒（本判据在本地退化为"同秒即重复"），只有跨越秒边界的那一小部分
/// 无法在本地识别（服务端 create_time 来自同步日志里的 ISO 时间戳，精度是毫秒）。
/// 同一秒内也无法用 id（Util.uuid() 是随机 UUIDv4，无时序语义）区分先后，
/// 必须借助 SQLite 隐式 rowid（严格按写入顺序递增）才能稳定保留"最早那条"。
class LearningLogRepair {
  LearningLogRepair._();

  /// 相邻两条日志被视为"同一次作答重复计分"的最大间隔。
  static const Duration duplicateInterval = Duration(milliseconds: 50);

  /// 修复全部用户的重复计分脏数据（幂等：重复执行不会再删行、不会再改值）。
  ///
  /// 整体放在一个事务里，避免中途失败留下"日志删了但 learning_words 没回填"的半成品。
  static Future<void> repairDuplicateLearningLogs(MyDatabase db) async {
    var deletedLogs = 0;
    var affectedWords = 0;

    await db.transaction(() async {
      // 跨用户扫表：迁移期没有"当前登录用户"，userId 一律取自每行的 user_id
      final rows = await (db.selectOnly(db.learningLogs, distinct: true)
            ..addColumns([db.learningLogs.userId]))
          .get();

      for (final row in rows) {
        final userId = row.read(db.learningLogs.userId)!;
        final result = await _repairUser(db, userId);
        deletedLogs += result.deletedLogs;
        affectedWords += result.affectedWords;
      }
    });

    Global.logger.i('🧹 [LearningLogRepair] 重复计分修复完成: 删除 $deletedLogs 条重复日志, 受影响 $affectedWords 个词');
  }

  /// 修复单个用户，返回 (删除的重复日志数, 受影响的词数)。
  static Future<({int deletedLogs, int affectedWords})> _repairUser(
    MyDatabase db,
    String userId,
  ) async {
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

    String? currentWordId;
    LearningLog? previous;
    for (final log in logs) {
      if (log.wordId != currentWordId) {
        currentWordId = log.wordId;
        previous = null;
      }

      final isDuplicate =
          previous != null && log.createTime.difference(previous.createTime) < duplicateInterval;
      if (isDuplicate) {
        duplicates.add(log);
      } else {
        lastSurvivors[log.wordId] = log;
      }
      // 判据是"与前一条的间隔"，因此无论当前条是否重复，都要成为下一条的比较基准
      previous = log;
    }

    if (duplicates.isEmpty) {
      return (deletedLogs: 0, affectedWords: 0);
    }

    // 1) 删除重复日志，并为每条删除写 learningLogs 的 DELETE 同步日志（客户端上报后服务端自动收敛）
    for (final duplicate in duplicates) {
      await (db.delete(db.learningLogs)..where((l) => l.id.equals(duplicate.id))).go();
      await DbLogUtil.logOperation(duplicate.userId, 'DELETE', 'learningLogs', duplicate.id, duplicate);
    }

    // 2) 用现存最后一条日志回填被污染的记忆字段；已掌握词跳过
    final masteredWordIds = await db.masteredWordsDao.getMasteredWordIdSet(userId);
    for (final entry in lastSurvivors.entries) {
      final learningWord = await db.learningWordsDao.getById(userId, entry.key);
      if (learningWord == null) {
        continue;
      }

      // 已掌握词（掌握线 stability >= 120，或已进入「已掌握」词书）不回填：
      // 掌握是用户可见、可编辑的事实，其 stability 是毕业哨兵值，不能按日志改回去
      final stability = learningWord.stability;
      if ((stability != null && stability >= Constants.graduationStability) ||
          masteredWordIds.contains(learningWord.wordId)) {
        continue;
      }

      final lastLog = entry.value;
      final restored = learningWord.copyWith(
        stability: Value(lastLog.stability),
        difficulty: Value(lastLog.difficulty),
        elapsedDays: Value(lastLog.elapsedDays),
        scheduledDays: Value(lastLog.scheduledDays),
      );
      // saveEntity 仅在值真正变化时落库，并以复合主键 userId-wordId 写 learningWords 的 UPDATE 同步日志
      await db.learningWordsDao.saveEntity(restored, true);
    }

    return (deletedLogs: duplicates.length, affectedWords: lastSurvivors.length);
  }
}
