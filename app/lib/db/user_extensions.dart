import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/api/vo.dart';

import 'package:nnbdc/util/user_helper.dart';
import 'package:nnbdc/util/level_util.dart';
import 'package:nnbdc/util/subscription_util.dart';

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

  /// 获取实际生效的每日单词数（非会员最多20个）
  int get effectiveWordsPerDay {
    int raw = wordsPerDay;
    if (raw == 0) return 0;
    if (!SubscriptionUtil.isPremium() && raw > 20) return 20;
    return raw;
  }
}
