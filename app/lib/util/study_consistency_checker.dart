import 'package:package_info_plus/package_info_plus.dart';

import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';

/// 数据自洽规则：客户端本地观察到的"数据自相矛盾"。
///
/// 判定口径必须与服务端保持一致，客户端只负责测量，不负责判定"该怎么修"。
/// 命中的事实会经 `reportSysError` 上报服务端（分类 CLIENT_DATA_INCONSISTENT），
/// 供服务端尽早发现成片的坏数据；**客户端不做任何静默修复**。
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

  final rule = judgeStudyConsistency(
    progress: learningWord.todayLearnedTimes,
    actualLogCount: logs.length,
  );
  if (rule == null) return null;

  final word = await db.wordsDao.getWordById(wordId);

  return StudyConsistencyViolation(
    rule: rule,
    wordId: wordId,
    spell: word != null && word.spell.isNotEmpty ? word.spell : wordId,
    progress: learningWord.todayLearnedTimes,
    actualLogCount: logs.length,
  );
}

/// 上报文本里带的客户端版本号：优先取安装包的 buildNumber（与 ver.json 的 verCode 同源），
/// 取不到时退回 pubspec 里的版本名，保证报告里一定有版本信息——这次那个问题就是集中在单一版本上的。
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
