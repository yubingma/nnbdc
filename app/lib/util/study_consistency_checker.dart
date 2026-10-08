import 'package:package_info_plus/package_info_plus.dart';

import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/learning_service.dart';
import 'package:nnbdc/util/study_steps_service.dart';

/// 数据自洽规则：客户端本地观察到的"数据自相矛盾"。
///
/// 判定口径与服务端保持严格一致：
/// 1. 不变式 1：今日评分流水条数不得大于今日环节进度（多出来说明同一次作答被重复写记录）
/// 2. 不变式 2：今日环节进度不得大于轨道长度上限（超过上限说明环节被多推进越界了）
/// 正常情况下，今日环节进度 >= 评分流水条数（因末尾 List 浏览环节不评分、提前掌握毕业不写后续流水）
/// 且今日环节进度 <= 轨道长度上限，属于绝对合法且普遍的正常背词完成态。
enum StudyConsistencyRule {
  /// 今日评分流水条数大于今日环节进度 —— 说明同一次作答被重复写了学习记录
  logsExceedProgress('logs_gt_progress'),

  /// 今日环节进度超过轨道长度上限 —— 说明环节被多推进越界了，
  /// 表现就是该词被夹在最后一个环节反复出题、答案已揭晓却没有可前进的出口。
  progressExceedsTrack('progress_gt_track'),
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
    this.trackLenMax,
  });

  final StudyConsistencyRule rule;
  final String wordId;
  final String spell;

  /// 记录的今日环节进展（learning_word.today_learned_times）
  final int progress;

  /// 今天真实的评分流水条数（learning_log 在业务日窗口内的条数）
  final int actualLogCount;

  /// 当前配置下轨道长度上限
  final int? trackLenMax;

  /// 组装上报文本：机器可解析的字段 + 人话说明，便于服务端聚合与人工快速定性
  ///
  /// 刻意只带实体 ID 与数值，不带单词释义、答案等学习内容。
  String toMessage(String clientVersion) {
    final buffer = StringBuffer();
    if (rule == StudyConsistencyRule.logsExceedProgress) {
      buffer
        ..writeln('规则=${rule.ruleId}（今日评分流水条数 大于 今日环节进度）')
        ..writeln('单词=$spell ($wordId)')
        ..writeln('实际值: progress=$progress, businessDayLogs=$actualLogCount')
        ..writeln('期望值: businessDayLogs 不得大于 progress')
        ..writeln('客户端版本=$clientVersion')
        ..write('说明: 同一次作答被重复写入了评分流水');
    } else {
      buffer
        ..writeln('规则=${rule.ruleId}（今日环节进度 超过 轨道长度上限）')
        ..writeln('单词=$spell ($wordId)')
        ..writeln('实际值: progress=$progress, trackLenMax=$trackLenMax')
        ..writeln('期望值: progress 不得超过 trackLenMax')
        ..writeln('客户端版本=$clientVersion')
        ..write('说明: 环节被多推进越界，该词会被夹在最后一个环节反复出题，'
            '用户看到的画面是答案已揭晓但没有可前进的出口，只能强行切走');
    }
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

/// 读取该用户当前配置下的轨道长度上限（新词/复习轨道取更长的一条，加上末尾固定的 List 浏览环节）
Future<int> resolveTrackLenMax(String userId) async {
  try {
    final service = StudyStepsService();
    final newCfg = await service.getThreeGroupConfig('new');
    final revCfg = await service.getThreeGroupConfig('review');
    final newAfterMax = [newCfg.correct.length, newCfg.wrong.length]
        .fold<int>(0, (a, b) => a > b ? a : b);
    final revAfterMax = [revCfg.correct.length, revCfg.wrong.length]
        .fold<int>(0, (a, b) => a > b ? a : b);
    final newMax = 1 + newAfterMax + 1; // 1 check + after + 1 List
    final revMax = 1 + revAfterMax + 1;
    return newMax > revMax ? newMax : revMax;
  } catch (e) {
    Global.logger.w('获取用户轨道长度上限失败，退回默认值 3: $e');
    return 3;
  }
}

/// 纯判定：给定"记录的今日进展"、"今天真实流水条数"与"轨道长度上限"，算出违反了哪条规则。
/// 抽成纯函数是为了让判定口径能被单元测试直接覆盖。
StudyConsistencyRule? judgeStudyConsistency({
  required int progress,
  required int actualLogCount,
  int? trackLenMax,
}) {
  // 今天一个环节都还没走完（进度为 0）时不以"流水条数"论短长：
  // 进度为 0 而今天有流水，绝大多数是"上一个业务日学过、这两天还没开始学"
  // —— 跨天复位已经把进度清零，属于正常状态。
  if (progress <= 0) return null;

  // 不变式 1：评分流水条数不得大于今日环节进度
  if (actualLogCount > progress) {
    return StudyConsistencyRule.logsExceedProgress;
  }

  // 不变式 2：今日环节进度不得超过轨道长度上限
  if (trackLenMax != null && trackLenMax > 0 && progress > trackLenMax) {
    return StudyConsistencyRule.progressExceedsTrack;
  }

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

  final trackLenMax = await resolveTrackLenMax(userId);

  // 业务日窗口 [03:00, 次日 03:00) 由 DAO 统一给出，不能用 AppClock.today() 当下界
  final logs = await db.learningLogsDao
      .getInBusinessDay(userId, wordIds: [wordId], instant: now);

  return judgeTodayWord(
    progress: learningWord.todayLearnedTimes,
    actualLogCount: logs.length,
    wordId: wordId,
    trackLenMax: trackLenMax,
  );
}

/// 用"今天已查到的流水条数"判定某个词是否不自洽（纯判定，不查库）。
StudyConsistencyViolation? judgeTodayWord({
  required int progress,
  required int actualLogCount,
  required String wordId,
  String? spell,
  int? trackLenMax,
}) {
  final rule = judgeStudyConsistency(
    progress: progress,
    actualLogCount: actualLogCount,
    trackLenMax: trackLenMax,
  );
  if (rule == null) return null;
  return StudyConsistencyViolation(
    rule: rule,
    wordId: wordId,
    spell: (spell == null || spell.isEmpty) ? wordId : spell,
    progress: progress,
    actualLogCount: actualLogCount,
    trackLenMax: trackLenMax,
  );
}

/// 扫描"今天已经进入学习队列的词"（batch_id > 0），列出所有不自洽的词。
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

  final trackLenMax = await resolveTrackLenMax(userId);

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
      trackLenMax: trackLenMax,
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

/// 修复某个词今天的学习自洽性（截断越界进度，或对齐流水条数）。
///
/// 这是用户在体检页**显式点确认**后才会走的路径，不是自动修复：
/// 调用方必须先把问题上报服务端（见 [reportStudyConsistency]），并把修复前后的数值写进日志。
///
/// [expectedProgress] 是用户在体检页看到、并据此确认的那个进度值：
/// 修复前会重新读一遍，若与它不一致（比如期间换了设备或跨了天），说明前提已变，直接放弃修复。
Future<StudyConsistencyRepairResult?> repairStudyConsistency({
  required String userId,
  required StudyConsistencyViolation violation,
  required int expectedProgress,
  required DateTime now,
  int? trackLenMax,
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

  final maxTrack = trackLenMax ?? await resolveTrackLenMax(userId);
  final logs = await db.learningLogsDao
      .getInBusinessDay(userId, wordIds: [violation.wordId], instant: now);
  final logCount = logs.length;

  int targetProgress = progressBefore;
  if (violation.rule == StudyConsistencyRule.progressExceedsTrack || progressBefore > maxTrack) {
    // 进度越界：截断至轨道上限（视为今日学完，退出出题队列，不再被夹在最后一环节反复出题）
    targetProgress = maxTrack;
  } else if (violation.rule == StudyConsistencyRule.logsExceedProgress || logCount > progressBefore) {
    // 流水多于进度：将进度补齐至真实流水条数（不超过轨道上限）
    targetProgress = logCount > maxTrack ? maxTrack : logCount;
  }

  if (targetProgress == progressBefore) {
    return StudyConsistencyRepairResult(
      wordId: violation.wordId,
      spell: violation.spell,
      progressBefore: progressBefore,
      progressAfter: progressBefore,
      logCount: logCount,
    );
  }

  await db.learningWordsDao.saveEntity(
    learningWord.copyWith(todayLearnedTimes: targetProgress),
    true, // 生成同步日志，让这次显式修复同步到云端与用户的其他设备
  );
  ThrottledDbSyncService().requestSync();

  Global.logger.i('🔧 [Consistency] 已修复学习进度与学习记录不一致: '
      'word=${violation.wordId}, progress $progressBefore -> $targetProgress, 今日记录 $logCount 条');

  return StudyConsistencyRepairResult(
    wordId: violation.wordId,
    spell: violation.spell,
    progressBefore: progressBefore,
    progressAfter: targetProgress,
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
