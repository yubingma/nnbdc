import 'package:nnbdc/db/db.dart';
import 'package:drift/drift.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/level_extensions.dart';

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
    int? lastLearningPosition,
    int? lastLearningMode,
    bool? learningFinished,
    bool? inviteAwardTaken,
    bool? isSuperAdmin,
    bool? isAdmin,
    bool? isInputor, 
    bool? isTodayLearningStarted,
    bool? isTodayLearningFinished,
    bool? autoPlaySentence,
    int? wordsPerDay,
    int? dakaDayCount,
    int? masteredWordsCount,
    int? cowDung,
    int? throwDiceChance,
    String? invitedById,
    String? levelId,
    int? continuousDakaDayCount,
    int? maxContinuousDakaDayCount,
    DateTime? lastDakaDate,
    int? totalScore,
    double? dakaRatio,
    bool? enableAllWrong,
    
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
      lastLearningPosition: lastLearningPosition ?? this.lastLearningPosition,
      lastLearningMode: lastLearningMode ?? this.lastLearningMode,
      learningFinished: learningFinished ?? this.learningFinished,
      inviteAwardTaken: inviteAwardTaken ?? this.inviteAwardTaken,
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
      isAdmin: isAdmin ?? this.isAdmin,
      isInputor: isInputor ?? this.isInputor,
      isTodayLearningStarted: isTodayLearningStarted ?? this.isTodayLearningStarted,
      isTodayLearningFinished: isTodayLearningFinished ?? this.isTodayLearningFinished,
      autoPlaySentence: autoPlaySentence ?? this.autoPlaySentence,
      wordsPerDay: wordsPerDay ?? this.wordsPerDay,
      dakaDayCount: dakaDayCount ?? this.dakaDayCount,
      masteredWordsCount: masteredWordsCount ?? this.masteredWordsCount,
      cowDung: cowDung ?? this.cowDung,
      throwDiceChance: throwDiceChance ?? this.throwDiceChance,
      invitedById: invitedById ?? this.invitedById,
      levelId: levelId ?? this.levelId,
      continuousDakaDayCount: continuousDakaDayCount ?? this.continuousDakaDayCount,
      maxContinuousDakaDayCount: maxContinuousDakaDayCount ?? this.maxContinuousDakaDayCount,
      lastDakaDate: lastDakaDate ?? this.lastDakaDate,
      totalScore: totalScore ?? this.totalScore,
      dakaRatio: dakaRatio ?? this.dakaRatio,
      enableAllWrong: enableAllWrong ?? this.enableAllWrong,
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
      lastLearningPosition: Value(lastLearningPosition),
      lastLearningMode: Value(lastLearningMode),
      learningFinished: Value(learningFinished),
      inviteAwardTaken: Value(inviteAwardTaken),
      isSuperAdmin: Value(isSuperAdmin),
      isAdmin: Value(isAdmin),
      isInputor: Value(isInputor),
      isTodayLearningStarted: Value(isTodayLearningStarted),
      isTodayLearningFinished: Value(isTodayLearningFinished),
      autoPlaySentence: Value(autoPlaySentence),
      wordsPerDay: Value(wordsPerDay),
      dakaDayCount: Value(dakaDayCount),
      masteredWordsCount: Value(masteredWordsCount),
      cowDung: Value(cowDung),
      throwDiceChance: Value(throwDiceChance),
      invitedById: Value(invitedById),
      levelId: Value(levelId),
      continuousDakaDayCount: Value(continuousDakaDayCount),
      maxContinuousDakaDayCount: Value(maxContinuousDakaDayCount),
      lastDakaDate: Value(lastDakaDate),
      totalScore: Value(totalScore),
      dakaRatio: Value(dakaRatio),
      enableAllWrong: Value(enableAllWrong),
      
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
      lastLearningPosition: Value(lastLearningPosition),
      lastLearningMode: Value(lastLearningMode),
      learningFinished: Value(learningFinished),
      inviteAwardTaken: Value(inviteAwardTaken),
      isSuperAdmin: Value(isSuperAdmin),
      isAdmin: Value(isAdmin),
      isInputor: Value(isInputor),
      isTodayLearningStarted: Value(isTodayLearningStarted),
      isTodayLearningFinished: Value(isTodayLearningFinished),
      autoPlaySentence: Value(autoPlaySentence),
      wordsPerDay: Value(wordsPerDay),
      dakaDayCount: Value(dakaDayCount),
      masteredWordsCount: Value(masteredWordsCount),
      cowDung: Value(cowDung),
      throwDiceChance: Value(throwDiceChance),
      invitedById: Value(invitedById),
      levelId: Value(levelId),
      continuousDakaDayCount: Value(continuousDakaDayCount),
      maxContinuousDakaDayCount: Value(maxContinuousDakaDayCount),
      lastDakaDate: Value(lastDakaDate),
      totalScore: Value(totalScore),
      dakaRatio: Value(dakaRatio),
      enableAllWrong: Value(enableAllWrong),
      
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
    userVo.lastLearningPosition = lastLearningPosition;
    userVo.lastLearningMode = lastLearningMode;
    userVo.learningFinished = learningFinished;
    userVo.inviteAwardTaken = inviteAwardTaken;
    userVo.isSuperAdmin = isSuperAdmin;
    userVo.isAdmin = isAdmin;
    userVo.isInputor = isInputor;
    userVo.isTodayLearningStarted = isTodayLearningStarted;
    userVo.isTodayLearningFinished = isTodayLearningFinished;
    userVo.autoPlaySentence = autoPlaySentence;
    userVo.wordsPerDay = wordsPerDay;
    userVo.dakaDayCount = dakaDayCount;
    userVo.masteredWordsCount = masteredWordsCount;
    userVo.cowDung = cowDung;
    userVo.throwDiceChance = throwDiceChance;
    
    // 处理invitedBy字段，这是一个UserVo类型
    // 我们不处理这个字段，因为这需要额外的数据库查询
    
    // 从数据库查询Level，并转换为LevelVo
    Level? lvl = await MyDatabase.instance.levelsDao.getLevelById(levelId);
    if (lvl != null) {
      userVo.level = lvl.toLevelVo();
    }
      
    userVo.continuousDakaDayCount = continuousDakaDayCount;
    userVo.maxContinuousDakaDayCount = maxContinuousDakaDayCount;
    userVo.lastDakaDate = lastDakaDate;
    userVo.totalScore = totalScore;
    userVo.dakaRatio = dakaRatio;
    userVo.enableAllWrong = enableAllWrong;
    
    
    return userVo;
  }
} 