import 'package:drift/drift.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/api/vo.dart';

import 'package:nnbdc/util/date_utils.dart';
import 'package:nnbdc/util/user_helper.dart';
import 'package:nnbdc/util/level_util.dart';
import 'package:nnbdc/services/user_privilege_manager.dart';

/// 把云端的整行 User 快照合并到本地时，保证「最近学习业务日」只进不退。
///
/// `lastLearningDate` 是跨天重置的唯一判据（见 StudyBo.getWord 的 isCrossDay）：
/// 云端的整行快照常由"根本不关心这个字段"的写入产生（例如对局结算只改 gameScore / cowDung），
/// 它携带的仍是客户端上传前的旧值。若照单全收，客户端刚完成的跨天重置会被打回昨天，
/// 用户当天每次点「开始学习」都会被判成 NEW_DAY，一整天进不了学习页。
///
/// 业务日按定义单调不减（时间只会往前走），所以取两者中较晚的一天即可；
/// 只有云端确实推进了业务日（多设备场景）时才采信云端值。
User mergeLatestLearningDay(User? local, User incoming) {
  if (local == null || local.lastLearningDate == null) return incoming;

  final localDay = DateUtils.businessDate(local.lastLearningDate!);
  final incomingDate = incoming.lastLearningDate;
  if (incomingDate == null) {
    return incoming.copyWith(lastLearningDate: Value(local.lastLearningDate));
  }

  final incomingDay = DateUtils.businessDate(incomingDate);
  if (!incomingDay.isBefore(localDay)) return incoming;
  return incoming.copyWith(lastLearningDate: Value(local.lastLearningDate));
}

/// User类的扩展方法
extension UserExtensions on User {
  /// 将User转换为UserVo
  Future<UserVo> toUserVo() async {
    final userVo = UserVo.c2(id);
    userVo.userName = userName;
    userVo.nickName = nickName;
    userVo.gameScore = gameScore;
    userVo.password = password;
    userVo.dakaScore = dakaScore;
    userVo.lastLoginTime = lastLoginTime;
    userVo.lastShareTime = lastShareTime;
    userVo.email = email;
    userVo.lastLearningDate = lastLearningDate;
    userVo.learnedDays = learnedDays;
    userVo.learningFinished = learningFinished;
    userVo.inviteAwardTaken = inviteAwardTaken;
    userVo.isSuperAdmin = isSuperAdmin;
    userVo.isAdmin = isAdmin;
    userVo.isInputor = isInputor;
    userVo.dakaDayCount = dakaDayCount;
    userVo.masteredWordsCount = masteredWordsCount;
    userVo.maxMasteredWords = maxMasteredWords ?? masteredWordsCount;
    // 魔法泡泡记录
    userVo.cowDung = cowDung;
    userVo.throwDiceChance = throwDiceChance;
    userVo.todayStudyStarted = todayStudyStarted;
    userVo.totalLearningSeconds = totalLearningSeconds ?? 0;
    userVo.todayLearningSeconds = todayLearningSeconds ?? 0;
    userVo.studyConfig = studyConfig;

    // 学习状态
    userVo.isTodayLearningStarted = UserHelper.isTodayLearningStartedFromUser(this);
    userVo.isTodayLearningFinished = UserHelper.isTodayLearningFinishedFromUser(this);

    // 处理invitedBy字段，这是一个UserVo类型
    // 我们不处理这个字段，因为这需要额外的数据库查询

    // 使用LevelUtil根据已掌握单词数计算等级
    userVo.level = LevelUtil.getLevelVoByWordCount(masteredWordsCount);

    userVo.continuousDakaDayCount = continuousDakaDayCount;
    userVo.maxContinuousDakaDayCount = maxContinuousDakaDayCount;
    userVo.lastDakaDate = lastDakaDate;

    userVo.dakaRatio = dakaRatio;

    // 订阅相关字段（iOS平台）
    userVo.isPremiumIos = isPremiumIos;
    userVo.subscriptionExpireDateIos = subscriptionExpireDateIos;
    userVo.subscriptionTypeIos = subscriptionTypeIos;
    userVo.subscriptionStatusIos = subscriptionStatusIos;

    // 通用会员字段
    userVo.vipExpireDate = vipExpireDate;
    userVo.vipType = vipType;
    userVo.lastPayChannel = lastPayChannel;

    // 强制会员字段
    userVo.premiumOverrideEnabled = premiumOverrideEnabled;
    userVo.premiumOverrideUpdateTime = premiumOverrideUpdateTime;
    userVo.premiumOverrideReason = premiumOverrideReason;
    userVo.premiumOverrideDuration = premiumOverrideDuration;

    return userVo;
  }

  /// 判断用户今天是否已经开始学习
  bool get isTodayLearningStarted => UserHelper.isTodayLearningStartedFromUser(this);

  /// 判断用户今天是否已经完成学习
  bool get isTodayLearningFinished => UserHelper.isTodayLearningFinishedFromUser(this);

  /// 获取实际生效的每日单词数（非会员受限，统一由权限管理器规范）
  int get effectiveWordsPerDay => UserPrivilegeManager.sanitizeDailyWords(wordsPerDay);
}
