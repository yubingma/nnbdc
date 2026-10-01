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

/// 纯判定：给定"记录的今日进展"与"今天真实流水条数"，算出违反了哪条规则。
/// 抽成纯函数是为了让判定口径能被单元测试直接覆盖。
StudyConsistencyRule? judgeStudyConsistency({
  required int progress,
  required int actualLogCount,
}) {
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

/// 扫描"今天已经进入学习队列的词"（batch_id > 0），列出所有不自洽的词。
///
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
  // 只在"进度多于记录"时下调；今天一条记录都没有时不改（没有可靠依据）
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
