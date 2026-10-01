import 'package:package_info_plus/package_info_plus.dart';

import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/learning_service.dart';

/// 数据自洽规则：客户端本地观察到的"数据自相矛盾"。
///
/// 判定口径必须与服务端保持一致，客户端只负责测量。
/// 命中的事实会经 `reportSysError` 上报服务端（分类 CLIENT_DATA_INCONSISTENT），
/// 供服务端尽早发现成片的坏数据。
/// 修复只走"用户在体检页显式确认"这一条路径（见 [repairStudyConsistency]），
/// 不做任何自动修复。
enum StudyConsistencyRule {
  /// 今日环节进度大于今天的评分流水条数 —— 说明同一次作答被重复推进了环节。
  /// 表现就是该词被夹在最后一个环节反复出题、答案已揭晓却没有可前进的出口。
  progressExceedsLogs('progress_gt_logs'),
  ;

  const StudyConsistencyRule(this.ruleId);

  /// 上报给服务端的稳定标识，服务端按它聚合告警，改名等于换规则
  final String ruleId;
}

/// 一条被判定为"不自洽"的现场记录
class StudyConsistencyViolation {
  const StudyConsistencyViolation({
    required this.rule,
    required this.wordId,
    required this.spell,
    required this.progress,
    required this.actualLogCount,
  });

  final StudyConsistencyRule rule;
  final String wordId;
  final String spell;

  /// 记录的今日环节进展（learning_word.today_learned_times）
  final int progress;

  /// 今天真实的评分流水条数（learning_log 在业务日窗口内的条数）
  final int actualLogCount;

  /// 组装上报文本：机器可解析的字段 + 人话说明，便于服务端聚合与人工快速定性
  ///
  /// 刻意只带实体 ID 与数值，不带单词释义、答案等学习内容。
  String toMessage(String clientVersion) {
    final buffer = StringBuffer()
      ..writeln('规则=${rule.ruleId}（今日环节进度 大于 今日评分流水条数）')
      ..writeln('单词=$spell ($wordId)')
      ..writeln('实际值: progress=$progress, businessDayLogs=$actualLogCount')
      ..writeln('期望值: progress 必须等于 businessDayLogs')
      ..writeln('客户端版本=$clientVersion')
      ..write('说明: 同一次作答被重复推进了环节，该词会被夹在最后一个环节反复出题，'
          '用户看到的画面是答案已揭晓但没有可前进的出口，只能强行切走');
    return buffer.toString();
  }
}

/// 同一个词在极短时间内被写下两条评分流水 —— 这是"同一次作答被计分两次"的第一现场，
/// 也正是"进度多一格、记录少一条"的上游成因。把它单独做成一类上报，
/// 是为了让将来再出现时能在事发现场留下证据，而不是只能靠毫秒值事后反推。
class DuplicateGradeViolation {
  const DuplicateGradeViolation({
    required this.wordId,
    required this.spell,
    required this.firstLogId,
    required this.secondLogId,
    required this.firstRating,
    required this.secondRating,
    required this.firstStability,
    required this.secondStability,
    required this.gapMilliseconds,
  });

  /// 同一词的两条评分流水间隔小于这个毫秒数就认为"不是两次人工作答"
  static const int duplicateWindowMilliseconds = 2000;

  final String wordId;
  final String spell;
  final String firstLogId;
  final String secondLogId;
  final int firstRating;
  final int secondRating;
  final double firstStability;
  final double secondStability;
  final int gapMilliseconds;

  /// 两条流水的记忆稳定度是否一字不差：若是，说明它们是**同一份前态**被算了两遍，
  /// 而不是"从第一条接着算第二条"
  bool get sameStability => (firstStability - secondStability).abs() < 1e-9;

  String toMessage(String clientVersion) {
    final buffer = StringBuffer()
      ..writeln('规则=duplicate_grade（同一词在 $duplicateWindowMilliseconds 毫秒内出现两条评分流水）')
      ..writeln('单词=$spell ($wordId)')
      ..writeln('先写入: id=$firstLogId, rating=$firstRating, stability=$firstStability')
      ..writeln('后写入: id=$secondLogId, rating=$secondRating, stability=$secondStability')
      ..writeln('间隔=${gapMilliseconds}ms, 两条稳定度相同=$sameStability')
      ..writeln('期望值: 同一个词在 $duplicateWindowMilliseconds 毫秒内只应有一条评分流水')
      ..writeln('客户端版本=$clientVersion')
      ..write('说明: 人手不可能在这个间隔内完成两次作答，说明同一次作答被多条提交路径'
          '各处理了一次；它会让环节进度比学习记录多一格，进而使该词被夹在最后一个环节反复出题');
    return buffer.toString();
  }
}

/// 纯判定：给定"记录的今日进展"与"今天真实流水条数"，算出违反了哪条规则。
/// 抽成纯函数是为了让判定口径能被单元测试直接覆盖。
StudyConsistencyRule? judgeStudyConsistency({
  required int progress,
  required int actualLogCount,
}) {
  // 今天一个环节都还没走完（进度为 0）时不以"流水条数"论短长：
  // 进度为 0 而今天有流水，绝大多数是"上一个业务日学过、这两天还没开始学"
  // —— 跨天复位已经把进度清零，属于正常状态。
  // 反过来，真正会让用户卡住的"进度领先于流水"必然出现在进度大于 0 的时候。
  if (progress <= 0) return null;
  if (progress > actualLogCount) return StudyConsistencyRule.progressExceedsLogs;
  return null;
}

/// 检查某一个词今天的数据是否自洽；不自洽时返回现场记录，自洽或查不到时返回 null。
///
/// 只读：只查 `learning_word`、`learning_log`、`word`，不改任何数据。
Future<StudyConsistencyViolation?> checkWordStudyConsistency({
  required String userId,
  required String wordId,
  required DateTime now,
}) async {
  final db = MyDatabase.instance;
  final learningWord = await db.learningWordsDao.getById(userId, wordId);
  if (learningWord == null || learningWord.todayLearnedTimes <= 0) return null;

  // 业务日窗口 [03:00, 次日 03:00) 由 DAO 统一给出，不能用 AppClock.today() 当下界
  final logs = await db.learningLogsDao
      .getInBusinessDay(userId, wordIds: [wordId], instant: now);

  return judgeTodayWord(
    progress: learningWord.todayLearnedTimes,
    actualLogCount: logs.length,
    wordId: wordId,
  );
}

/// 用"今天已查到的流水条数"判定某个词是否不自洽（纯判定，不查库）。
StudyConsistencyViolation? judgeTodayWord({
  required int progress,
  required int actualLogCount,
  required String wordId,
  String? spell,
}) {
  final rule = judgeStudyConsistency(progress: progress, actualLogCount: actualLogCount);
  if (rule == null) return null;
  return StudyConsistencyViolation(
    rule: rule,
    wordId: wordId,
    spell: (spell == null || spell.isEmpty) ? wordId : spell,
    progress: progress,
    actualLogCount: actualLogCount,
  );
}

/// 扫描"今天已经进入学习队列的词"（batch_id > 0），列出所有不自洽的词。///
/// 供用户可见的"数据健康检查"页面体检使用：这些词才是用户当下会遇到的那一批，
/// 只查它们既够用又便宜，不需要扫全库。只读，不改任何数据。
Future<List<StudyConsistencyViolation>> scanTodayStudyConsistency({
  required String userId,
  required DateTime now,
}) async {
  final words = await LearningService.getTodayLearningWordsFromDb(userId);
  final candidates =
      words.where((w) => w.todayLearnedTimes > 0).toList(growable: false);
  if (candidates.isEmpty) return const [];

  // 一次查完这批词今天的学习记录，按词统计条数，避免逐个词查库
  final logs = await MyDatabase.instance.learningLogsDao.getInBusinessDay(
    userId,
    wordIds: candidates.map((w) => w.wordId),
    instant: now,
  );
  final logCounts = <String, int>{};
  for (final log in logs) {
    logCounts[log.wordId] = (logCounts[log.wordId] ?? 0) + 1;
  }

  final violations = <StudyConsistencyViolation>[];
  for (final word in candidates) {
    final violation = judgeTodayWord(
      progress: word.todayLearnedTimes,
      actualLogCount: logCounts[word.wordId] ?? 0,
      wordId: word.wordId,
    );
    if (violation != null) violations.add(violation);
  }
  return violations;
}

/// 判定"极短间隔重复计分"时用到的单条流水摘要（把判定与 Drift 实体解耦）
class GradeLogSummary {
  const GradeLogSummary({
    required this.id,
    required this.rating,
    required this.stability,
    required this.createTime,
  });

  final String id;
  final int rating;
  final double stability;
  final DateTime createTime;
}

/// 从"某个词今天的评分流水（按时间正序）"里找出极短间隔的两条，判定为"同一次作答被计分两次"。
///
/// 抽成纯函数：判定口径可被单元测试直接覆盖，也不依赖数据库。
/// 只取**时间上相邻**的两条比较，不拿首尾去比——中间隔着别的作答就不能算重复。
DuplicateGradeViolation? judgeDuplicateGrade({
  required String wordId,
  required String spell,
  required List<GradeLogSummary> logs,
}) {
  if (logs.length < 2) return null;
  for (var i = 1; i < logs.length; i++) {
    final previous = logs[i - 1];
    final current = logs[i];
    final gap = current.createTime.difference(previous.createTime).inMilliseconds;
    if (gap >= 0 && gap < DuplicateGradeViolation.duplicateWindowMilliseconds) {
      return DuplicateGradeViolation(
        wordId: wordId,
        spell: spell,
        firstLogId: previous.id,
        secondLogId: current.id,
        firstRating: previous.rating,
        secondRating: current.rating,
        firstStability: previous.stability,
        secondStability: current.stability,
        gapMilliseconds: gap,
      );
    }
  }
  return null;
}

/// 读取某个词今天的评分流水，判定是否存在"极短间隔的两条"。
///
/// 只读：只查 `learning_log` 与 `word`，不改任何数据。
Future<DuplicateGradeViolation?> checkWordDuplicateGrade({
  required String userId,
  required String wordId,
  required DateTime now,
}) async {
  final db = MyDatabase.instance;
  final logs = await db.learningLogsDao
      .getInBusinessDay(userId, wordIds: [wordId], instant: now);
  if (logs.length < 2) return null;

  final word = await db.wordsDao.getWordById(wordId);
  return judgeDuplicateGrade(
    wordId: wordId,
    spell: (word != null && word.spell.isNotEmpty) ? word.spell : wordId,
    logs: logs
        .map((l) => GradeLogSummary(
              id: l.id,
              rating: l.rating,
              stability: l.stability,
              createTime: l.createTime,
            ))
        .toList(growable: false),
  );
}

/// 修复结果
class StudyConsistencyRepairResult {
  const StudyConsistencyRepairResult({
    required this.wordId,
    required this.spell,
    required this.progressBefore,
    required this.progressAfter,
    required this.logCount,
  });

  final String wordId;
  final String spell;
  final int progressBefore;
  final int progressAfter;
  final int logCount;

  /// 本次是否真的改了数据
  bool get changed => progressBefore != progressAfter;
}

/// 把某个词今天的环节进度改回"今天的评分流水条数"。
///
/// 只做**下调**（`progress > logs` 才动作）：
/// - 往下改对应的是"同一次作答被重复推进了环节"，不会凭空抹掉用户真实走完的环节；
/// - 往上补齐（`progress < logs`）没有依据，而且会把用户没在本机做过的环节直接放行，一律不做。
///
/// 这是用户在体检页**显式点确认**后才会走的路径，不是自动修复：
/// 调用方必须先把问题上报服务端（见 [reportStudyConsistency]），并把修复前后的数值写进日志，
/// 这样数据即使被改小，服务端仍然留有可追溯的现场记录。
///
/// [expectedProgress] 是用户在体检页看到、并据此确认的那个进度值：
/// 修复前会重新读一遍，若与它不一致（比如期间换了设备或跨了天），说明前提已变，直接放弃修复。
Future<StudyConsistencyRepairResult?> repairStudyConsistency({
  required String userId,
  required StudyConsistencyViolation violation,
  required int expectedProgress,
  required DateTime now,
}) async {
  final db = MyDatabase.instance;
  final learningWord = await db.learningWordsDao.getById(userId, violation.wordId);
  if (learningWord == null) return null;

  final progressBefore = learningWord.todayLearnedTimes;
  // 前提校验：用户确认时看到的状态必须仍然成立，否则宁可不修
  if (progressBefore != expectedProgress) {
    Global.logger.w('⚠️ [Consistency] 修复前提已变化（当前进度 $progressBefore，'
        '确认时为 $expectedProgress），放弃修复: ${violation.wordId}');
    return null;
  }

  final logs = await db.learningLogsDao
      .getInBusinessDay(userId, wordIds: [violation.wordId], instant: now);
  final logCount = logs.length;

  // 今天一条记录都没有："对不上"可能只是跨天复位与同步的时序差异，
  // 没有可靠依据判断该整成几，动它等于把进度抹成 0，一律不修。
  // （体检页已把这种情况写清：今天没有任何学习记录时不会改动。）
  if (logCount == 0) {
    Global.logger.w('⚠️ [Consistency] 今天没有任何学习记录，放弃修复: ${violation.wordId}');
    return StudyConsistencyRepairResult(
      wordId: violation.wordId,
      spell: violation.spell,
      progressBefore: progressBefore,
      progressAfter: progressBefore,
      logCount: logCount,
    );
  }

  // 只在"进度多于记录"时下调；"进度少于记录"（多设备抢跑等）不往上补齐
  if (progressBefore <= logCount) {
    return StudyConsistencyRepairResult(
      wordId: violation.wordId,
      spell: violation.spell,
      progressBefore: progressBefore,
      progressAfter: progressBefore,
      logCount: logCount,
    );
  }

  await db.learningWordsDao.saveEntity(
    learningWord.copyWith(todayLearnedTimes: logCount),
    true, // 生成同步日志，让这次显式修复同步到云端与用户的其他设备
  );
  ThrottledDbSyncService().requestSync();

  Global.logger.i('🔧 [Consistency] 已修复学习进度与学习记录不一致: '
      'word=${violation.wordId}, progress $progressBefore -> $logCount, 今日记录 $logCount 条');

  return StudyConsistencyRepairResult(
    wordId: violation.wordId,
    spell: violation.spell,
    progressBefore: progressBefore,
    progressAfter: logCount,
    logCount: logCount,
  );
}

/// 上报/日志文本里带的客户端版本号：优先取安装包的 buildNumber（与 ver.json 的 verCode 同源），
/// 取不到时退回版本名，保证记录里一定有版本信息——这类坏数据往往是集中在单一版本上的。
Future<String> resolveClientVersion() async {
  final cached = _clientVersion;
  if (cached != null) return cached;
  try {
    final info = await PackageInfo.fromPlatform();
    _clientVersion =
        info.buildNumber.isNotEmpty ? info.buildNumber : info.version;
  } catch (e) {
    Global.logger.w('获取客户端版本号失败，上报将使用 unknown: $e');
    _clientVersion = 'unknown';
  }
  return _clientVersion!;
}

String? _clientVersion;
