import 'package:nnbdc/db/db.dart';
import 'package:drift/drift.dart';
import 'package:nnbdc/api/vo.dart';

import 'package:nnbdc/util/user_helper.dart';
import 'package:nnbdc/util/level_util.dart';

/// User类的扩展方法
extension UserExtensions on User {
  /// 创建User对象的副本，只修改指定的字段
  User copyWith({
    String? id,
    String? userName,
    String? nickName,
    int? gameScore,
    String? password,
    int? dakaScore,
    bool? showAnswersDirectly,
    bool? autoPlayWord,
    DateTime? lastLoginTime,
    DateTime? lastShareTime,
    String? email,
    DateTime? lastLearningDate,
    int? learnedDays,
    bool? learningFinished,
    bool? inviteAwardTaken,
    bool? isSuperAdmin,
    bool? isAdmin,
    bool? isInputor,
    bool? autoPlaySentence,
    int? wordsPerDay,
    int? dakaDayCount,
    int? masteredWordsCount,
    int? cowDung,
    int? throwDiceChance,
    String? invitedById,
    int? continuousDakaDayCount,
    int? maxContinuousDakaDayCount,
    DateTime? lastDakaDate,
    double? dakaRatio,
    bool? enableAllWrong,
    // iOS订阅字段
    bool? isPremiumIos,
    DateTime? subscriptionExpireDateIos,
    String? subscriptionTypeIos,
    String? subscriptionStatusIos,
    String? lastReceiptDataIos,

    // 强制会员字段
    bool? premiumOverrideEnabled,
    DateTime? premiumOverrideUpdateTime,
    String? premiumOverrideReason,
    String? premiumOverrideDuration,
  }) {
    return User(
      id: id ?? this.id,
      userName: userName ?? this.userName,
      nickName: nickName ?? this.nickName,
      gameScore: gameScore ?? this.gameScore,
      password: password ?? this.password,
      dakaScore: dakaScore ?? this.dakaScore,
      showAnswersDirectly: showAnswersDirectly ?? this.showAnswersDirectly,
      autoPlayWord: autoPlayWord ?? this.autoPlayWord,
      lastLoginTime: lastLoginTime ?? this.lastLoginTime,
      lastShareTime: lastShareTime ?? this.lastShareTime,
      email: email ?? this.email,
      lastLearningDate: lastLearningDate ?? this.lastLearningDate,
      learnedDays: learnedDays ?? this.learnedDays,
      learningFinished: learningFinished ?? this.learningFinished,
      inviteAwardTaken: inviteAwardTaken ?? this.inviteAwardTaken,
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
      isAdmin: isAdmin ?? this.isAdmin,
      isInputor: isInputor ?? this.isInputor,

      autoPlaySentence: autoPlaySentence ?? this.autoPlaySentence,
      wordsPerDay: wordsPerDay ?? this.wordsPerDay,
      dakaDayCount: dakaDayCount ?? this.dakaDayCount,
      masteredWordsCount: masteredWordsCount ?? this.masteredWordsCount,
      cowDung: cowDung ?? this.cowDung,
      throwDiceChance: throwDiceChance ?? this.throwDiceChance,
      invitedById: invitedById ?? this.invitedById,

      continuousDakaDayCount: continuousDakaDayCount ?? this.continuousDakaDayCount,
      maxContinuousDakaDayCount: maxContinuousDakaDayCount ?? this.maxContinuousDakaDayCount,
      lastDakaDate: lastDakaDate ?? this.lastDakaDate,

      dakaRatio: dakaRatio ?? this.dakaRatio,
      enableAllWrong: enableAllWrong ?? this.enableAllWrong,
      // iOS订阅字段
      isPremiumIos: isPremiumIos ?? this.isPremiumIos,
      subscriptionExpireDateIos: subscriptionExpireDateIos ?? this.subscriptionExpireDateIos,
      subscriptionTypeIos: subscriptionTypeIos ?? this.subscriptionTypeIos,
      subscriptionStatusIos: subscriptionStatusIos ?? this.subscriptionStatusIos,
      lastReceiptDataIos: lastReceiptDataIos ?? this.lastReceiptDataIos,

      // 强制会员字段
      premiumOverrideEnabled: premiumOverrideEnabled ?? this.premiumOverrideEnabled,
      premiumOverrideUpdateTime: premiumOverrideUpdateTime ?? this.premiumOverrideUpdateTime,
      premiumOverrideReason: premiumOverrideReason ?? this.premiumOverrideReason,
      premiumOverrideDuration: premiumOverrideDuration ?? this.premiumOverrideDuration, 
      
      todayStudyStarted: false,
    );
  }

  /// 创建UsersCompanion对象，用于Drift数据库更新
  UsersCompanion toCompanion() {
    return UsersCompanion(
      id: Value(id),
      userName: Value(userName),
      nickName: Value(nickName),
      gameScore: Value(gameScore),
      password: Value(password),
      dakaScore: Value(dakaScore),
      showAnswersDirectly: Value(showAnswersDirectly),
      autoPlayWord: Value(autoPlayWord),
      lastLoginTime: Value(lastLoginTime),
      lastShareTime: Value(lastShareTime),
      email: Value(email),
      lastLearningDate: Value(lastLearningDate),
      learnedDays: Value(learnedDays),
      learningFinished: Value(learningFinished),
      inviteAwardTaken: Value(inviteAwardTaken),
      isSuperAdmin: Value(isSuperAdmin),
      isAdmin: Value(isAdmin),
      isInputor: Value(isInputor),
      autoPlaySentence: Value(autoPlaySentence),
      wordsPerDay: Value(wordsPerDay),
      dakaDayCount: Value(dakaDayCount),
      masteredWordsCount: Value(masteredWordsCount),
      cowDung: Value(cowDung),
      throwDiceChance: Value(throwDiceChance),
      invitedById: Value(invitedById),

      continuousDakaDayCount: Value(continuousDakaDayCount),
      maxContinuousDakaDayCount: Value(maxContinuousDakaDayCount),
      lastDakaDate: Value(lastDakaDate),
      dakaRatio: Value(dakaRatio),
      enableAllWrong: Value(enableAllWrong),
      // iOS订阅字段
      isPremiumIos: Value(isPremiumIos),
      subscriptionExpireDateIos: Value(subscriptionExpireDateIos),
      subscriptionTypeIos: Value(subscriptionTypeIos),
      subscriptionStatusIos: Value(subscriptionStatusIos),
      lastReceiptDataIos: Value(lastReceiptDataIos),

      // 强制会员字段
      premiumOverrideEnabled: Value(premiumOverrideEnabled),
      premiumOverrideUpdateTime: Value(premiumOverrideUpdateTime),
      premiumOverrideReason: Value(premiumOverrideReason),
      premiumOverrideDuration: Value(premiumOverrideDuration),
    );
  }

  /// 创建UsersCompanion对象，用于Drift数据库更新
  UsersCompanion toCompanionForUpdate() {
    return UsersCompanion(
      id: Value(id),
      userName: Value(userName),
      nickName: Value(nickName),
      gameScore: Value(gameScore),
      password: Value(password),
      dakaScore: Value(dakaScore),
      showAnswersDirectly: Value(showAnswersDirectly),
      autoPlayWord: Value(autoPlayWord),
      lastLoginTime: Value(lastLoginTime),
      lastShareTime: Value(lastShareTime),
      email: Value(email),
      lastLearningDate: Value(lastLearningDate),
      learnedDays: Value(learnedDays),
      learningFinished: Value(learningFinished),
      inviteAwardTaken: Value(inviteAwardTaken),
      isSuperAdmin: Value(isSuperAdmin),
      isAdmin: Value(isAdmin),
      isInputor: Value(isInputor),
      autoPlaySentence: Value(autoPlaySentence),
      wordsPerDay: Value(wordsPerDay),
      dakaDayCount: Value(dakaDayCount),
      masteredWordsCount: Value(masteredWordsCount),
      cowDung: Value(cowDung),
      throwDiceChance: Value(throwDiceChance),
      invitedById: Value(invitedById),

      continuousDakaDayCount: Value(continuousDakaDayCount),
      maxContinuousDakaDayCount: Value(maxContinuousDakaDayCount),
      lastDakaDate: Value(lastDakaDate),
      dakaRatio: Value(dakaRatio),
      enableAllWrong: Value(enableAllWrong),
      // iOS订阅字段
      isPremiumIos: Value(isPremiumIos),
      subscriptionExpireDateIos: Value(subscriptionExpireDateIos),
      subscriptionTypeIos: Value(subscriptionTypeIos),
      subscriptionStatusIos: Value(subscriptionStatusIos),
      lastReceiptDataIos: Value(lastReceiptDataIos),

      // 强制会员字段
      premiumOverrideEnabled: Value(premiumOverrideEnabled),
      premiumOverrideUpdateTime: Value(premiumOverrideUpdateTime),
      premiumOverrideReason: Value(premiumOverrideReason),
      premiumOverrideDuration: Value(premiumOverrideDuration),
    );
  }

  /// 将User转换为UserVo
  Future<UserVo> toUserVo() async {
    final userVo = UserVo.c2(id);
    userVo.userName = userName;
    userVo.nickName = nickName;
    userVo.gameScore = gameScore;
    userVo.password = password;
    userVo.dakaScore = dakaScore;
    userVo.showAnswersDirectly = showAnswersDirectly;
    userVo.autoPlayWord = autoPlayWord;
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
    userVo.autoPlaySentence = autoPlaySentence;
    userVo.wordsPerDay = wordsPerDay;
    userVo.dakaDayCount = dakaDayCount;
    userVo.masteredWordsCount = masteredWordsCount;
    // 魔法泡泡记录
    userVo.cowDung = cowDung;
    userVo.throwDiceChance = throwDiceChance;

    // 学习状态
    userVo.isTodayLearningStarted = UserHelper.isTodayLearningStartedFromUser(this);
    userVo.isTodayLearningFinished = UserHelper.isTodayLearningFinishedFromUser(this);

    // 处理invitedBy字段，这是一个UserVo类型
    // 我们不处理这个字段，因为这需要额外的数据库查询

    // 使用LevelUtil根据总积分计算等级
    userVo.level = LevelUtil.getLevelVoByScore(UserHelper.getTotalScoreFromUser(this));

    userVo.continuousDakaDayCount = continuousDakaDayCount;
    userVo.maxContinuousDakaDayCount = maxContinuousDakaDayCount;
    userVo.lastDakaDate = lastDakaDate;

    userVo.dakaRatio = dakaRatio;
    userVo.enableAllWrong = enableAllWrong;

    // 订阅相关字段（iOS平台）
    userVo.isPremiumIos = isPremiumIos;
    userVo.subscriptionExpireDateIos = subscriptionExpireDateIos;
    userVo.subscriptionTypeIos = subscriptionTypeIos;
    userVo.subscriptionStatusIos = subscriptionStatusIos;

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
}
