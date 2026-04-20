import 'package:drift/drift.dart';

// 本地参数表
class LocalParams extends Table {
  TextColumn get name => text()();

  TextColumn get value => text()();

  TextColumn get description => text().nullable()();

  @override
  Set<Column>? get primaryKey => {name};
}

// 用户学习步骤表
class UserStudySteps extends Table {
  TextColumn get userId => text()();

  TextColumn get studyStep => text()();

  IntColumn get seq => integer()();

  TextColumn get state => text()(); // 'Active', 'Inactive'

  DateTimeColumn get createTime => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {userId, studyStep};
}

class VotedSentences extends Table {
  TextColumn get userId => text()();

  TextColumn get sentenceId => text()();

  TextColumn get vote => text()(); // 'HAND'/'FOOT'

  @override
  Set<Column>? get primaryKey => {userId, sentenceId};
}

class VotedWordImages extends Table {
  TextColumn get userId => text()();

  TextColumn get imageId => text()();

  TextColumn get vote => text()(); // 'HAND'/'FOOT'

  @override
  Set<Column>? get primaryKey => {userId, imageId};
}

class DictGroups extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get parentId => text().nullable()();

  IntColumn get displayIndex => integer()();

  @override
  Set<Column>? get primaryKey => {id};
}

class Users extends Table {
  TextColumn get id => text()();

  TextColumn get userName => text()();

  TextColumn get nickName => text().nullable()();

  IntColumn get gameScore => integer()();

  TextColumn get password => text().nullable()();

  /// 打卡积分-
  IntColumn get dakaScore => integer()();

  DateTimeColumn get lastLoginTime => dateTime().nullable()();

  DateTimeColumn get lastShareTime => dateTime().nullable()();

  TextColumn get email => text().nullable()();

  // 微信相关字段
  TextColumn get wechatOpenId => text().nullable()();
  TextColumn get wechatUnionId => text().nullable()();
  TextColumn get wechatNickname => text().nullable()();
  TextColumn get wechatAvatar => text().nullable()();

  DateTimeColumn get lastLearningDate => dateTime().nullable()();

  // 累计学习天数，记录用户从开始使用app以来，总共学习了多少天(不是用户存在了多少天)。
  IntColumn get learnedDays => integer()();

  // IntColumn get lastLearningPosition => integer().nullable()(); // 已废弃，进化为动态计算进度

  // IntColumn get lastLearningMode => integer().nullable()(); // 已废弃，进化为动态计算进度

  BoolColumn get learningFinished => boolean().nullable().withDefault(const Constant(false))();

  BoolColumn get inviteAwardTaken => boolean().nullable().withDefault(const Constant(false))();

  BoolColumn get isSuperAdmin => boolean().nullable().withDefault(const Constant(false))();

  BoolColumn get isAdmin => boolean().nullable().withDefault(const Constant(false))();

  BoolColumn get isInputor => boolean().nullable().withDefault(const Constant(false))();

  IntColumn get wordsPerDay => integer()();

  IntColumn get dakaDayCount => integer()();

  IntColumn get masteredWordsCount => integer()();

  IntColumn get cowDung => integer()();

  IntColumn get throwDiceChance => integer()();

  TextColumn get invitedById => text().nullable()();

  /// 连续打卡天数
  IntColumn get continuousDakaDayCount => integer()();

  /// 最大连续打卡天数
  IntColumn get maxContinuousDakaDayCount => integer()();

  /// 最近一次打卡的日期
  DateTimeColumn get lastDakaDate => dateTime().nullable()();

  RealColumn get dakaRatio => real().nullable()();

  /// 今日学习是否已经开始（点击了今日学习计划页面的“开始学习”按钮）
  BoolColumn get todayStudyStarted => boolean().withDefault(const Constant(false))();

  /// 学习总时长（秒）
  IntColumn get totalLearningSeconds => integer().nullable().withDefault(const Constant(0))();

  /// 今日学习时长（秒）
  IntColumn get todayLearningSeconds => integer().nullable().withDefault(const Constant(0))();

  // 苹果登录相关字段
  TextColumn get appleUserId => text().nullable()();

  // 订阅相关字段（仅支持iOS平台）

  // iOS订阅字段
  /// iOS是否为会员
  BoolColumn get isPremiumIos => boolean().nullable().withDefault(const Constant(false))();

  /// iOS订阅到期时间
  DateTimeColumn get subscriptionExpireDateIos => dateTime().nullable()();

  /// iOS订阅类型：monthly/annual
  TextColumn get subscriptionTypeIos => text().nullable()();

  /// iOS订阅状态：active/expired/cancelled
  TextColumn get subscriptionStatusIos => text().nullable()();

  /// iOS最后验证的收据数据（用于恢复购买）
  TextColumn get lastReceiptDataIos => text().nullable()();

  // 强制视为会员（用于纠纷处理/白名单/补偿等）
  BoolColumn get premiumOverrideEnabled => boolean().nullable().withDefault(const Constant(false))();

  /// 强制会员状态最后修改时间
  DateTimeColumn get premiumOverrideUpdateTime => dateTime().nullable()();

  /// 强制会员状态修改原因
  TextColumn get premiumOverrideReason => text().nullable()();

  /// 强制会员状态延续时长（形如：10天/360秒/15分钟；null 表示永久）
  TextColumn get premiumOverrideDuration => text().nullable()();

  // 旧字段 passIfSpeakOutOneMeaning 已移除

  /// 学习偏好配置 (JSON格式，目前主要用来包裹 walkman 配置及其他后续动态配置)
  TextColumn get studyConfig => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LearningDicts extends Table {
  TextColumn get userId => text()();

  TextColumn get dictId => text()();

  BoolColumn get isPrivileged => boolean()();
  BoolColumn get fetchMastered => boolean()();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {userId, dictId};
}

class Dicts extends Table {
  TextColumn get id => text()();

  BoolColumn get isReady => boolean()();

  BoolColumn get isShared => boolean()();

  TextColumn get name => text()();

  IntColumn get wordCount => integer()();

  TextColumn get ownerId => text().withDefault(const Constant('15118'))();

  BoolColumn get visible => boolean()();
  
  BoolColumn get editable => boolean().withDefault(const Constant(false))();
  
  BoolColumn get deletable => boolean().withDefault(const Constant(true))();

  IntColumn get popularityLimit => integer().nullable()();

  TextColumn get domain => text().nullable()();

  TextColumn get baseDictId => text().nullable()();

  TextColumn get coverUrl => text().nullable()();

  TextColumn get sortAlg => text().nullable()();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {id};
}

class Words extends Table {
  TextColumn get id => text()();

  TextColumn get americaPronounce => text().nullable()();

  TextColumn get britishPronounce => text().nullable()();

  TextColumn get groupInfo => text().nullable()();

  TextColumn get longDesc => text().nullable()();

  IntColumn get popularity => integer()();

  TextColumn get pronounce => text().nullable()();

  TextColumn get shortDesc => text().nullable()();

  TextColumn get spell => text()();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {id};
}

class UserDbLogs extends Table {
  TextColumn get id => text()();

  TextColumn get operate => text()();

  TextColumn get recordId => text()();

  TextColumn get record => text()();

  TextColumn get tblName => text()();

  TextColumn get userId => text()();

  IntColumn get version => integer()();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime()();

  @override
  Set<Column>? get primaryKey => {id};
}

class UserDbVersions extends Table {
  TextColumn get userId => text()();

  IntColumn get version => integer()();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {userId};
}

class DictWords extends Table {
  TextColumn get dictId => text()();

  TextColumn get wordId => text()();

  /// 单词在单词书中的顺序号，从1开始
  IntColumn get seq => integer()();

  /// 单词所属单元序号，0 表示无单元
  IntColumn get unit => integer().withDefault(const Constant(0))();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {dictId, wordId};
}

class WordImages extends Table {
  TextColumn get id => text()();

  TextColumn get imageFile => text()();

  IntColumn get foot => integer()();

  IntColumn get hand => integer()();

  TextColumn get authorId => text()();
  TextColumn get ownerId => text().withDefault(const Constant('15118'))();

  TextColumn get wordId => text()();
  TextColumn get status => text().nullable()();
  TextColumn get auditReason => text().nullable()();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {id};
}

class VerbTenses extends Table {
  TextColumn get id => text()();

  TextColumn get tenseType => text()();

  TextColumn get tensedSpell => text().nullable()();

  TextColumn get wordId => text().nullable()();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {id};
}

class Synonyms extends Table {
  TextColumn get meaningItemId => text()();

  TextColumn get wordId => text()();
  TextColumn get spell => text()();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {meaningItemId, wordId};
}

class SimilarWords extends Table {
  TextColumn get wordId => text()();

  TextColumn get similarWordId => text()();
  TextColumn get similarWordSpell => text()();

  IntColumn get distance => integer()();

  @override
  Set<Column>? get primaryKey => {wordId, similarWordId};
}

class Cigens extends Table {
  TextColumn get id => text()();

  TextColumn get description => text()();

  TextColumn get spell => text().nullable()();

  TextColumn get category => text().nullable()();

  TextColumn get meaningCn => text().nullable()();

  TextColumn get meaningEn => text().nullable()();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {id};
}

class CigenWordLinks extends Table {
  TextColumn get cigenId => text()();

  TextColumn get wordId => text()();

  TextColumn get theExplain => text()();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {cigenId, wordId};
}

class MeaningItems extends Table {
  TextColumn get id => text()();
  TextColumn get wordId => text()();
  TextColumn get dictId => text().nullable()();

  TextColumn get ciXing => text()();

  TextColumn get meaning => text()();

  IntColumn get popularity => integer().withDefault(const Constant(999))();

  DateTimeColumn get createTime => dateTime()();
  TextColumn get ownerId => text().withDefault(const Constant('15118'))();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {id};
}

class Sentences extends Table {
  TextColumn get id => text()();

  TextColumn get english => text()();

  TextColumn get chinese => text()();
  TextColumn get englishDigest => text()();
  TextColumn get partOfSpeech => text().nullable()();
  TextColumn get theType => text()();

  IntColumn get handCount => integer()();

  IntColumn get footCount => integer()();

  TextColumn get authorId => text()();
  TextColumn get ownerId => text().withDefault(const Constant('15118'))();

  TextColumn get meaningItemId => text()();

  TextColumn get wordMeaning => text()();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {id};
}

class LearningWords extends Table {
  TextColumn get userId => text()();
  TextColumn get wordId => text()();
  IntColumn get addDay => integer()();
  DateTimeColumn get addTime => dateTime()();
  DateTimeColumn get lastLearningDate => dateTime().nullable()();
  IntColumn get learningOrder => integer()();

  /// 取词批次ID (Select Batch ID)
  /// 注意：这是在每天学习前"准备今日学习计划"时取词的批次标记，
  /// 用于标识单词是同一次被拉取进入计划的，并非用户开始学习后每 10 个词一组的"学习小批次(Learning Batch/Chunk)"！
  /// 唯一标识：判断该单词是否属于“今日待学/复习单词”的唯一依据。
  /// 此字段 > 0 即代表该词被选中列入了今日计划。将其设为 0 即可将其移出今日特遣队而不影响其原有的 FSRS 历史。
  /// nullable() to handle legacy data where batch_id might be NULL
  IntColumn get batchId => integer().nullable()();


  /// FSRS 算法相关字段
  RealColumn get stability => real().nullable()();
  RealColumn get difficulty => real().nullable()();
  IntColumn get elapsedDays => integer().nullable()();
  IntColumn get scheduledDays => integer().nullable()();
  IntColumn get reps => integer().nullable()();
  IntColumn get lapses => integer().nullable()();
  IntColumn get state => integer().nullable().withDefault(const Constant(0))(); // FSRS状态：0: New (新词), 1: Learning (学习中), 2: Review (复习), 3: Relearning (重学)

  BoolColumn get isTodayNewWord => boolean()();
  IntColumn get learnedTimes => integer()();
  IntColumn get todayLearnedTimes => integer().withDefault(const Constant(0))();

  DateTimeColumn get createTime => dateTime()();

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {userId, wordId};
}

class BookMarks extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get bookMarkName => text()();
  TextColumn get spell => text()();
  IntColumn get position => integer()();
  DateTimeColumn get createTime => dateTime()();
  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {id};

  @override
  List<String> get customConstraints => ['UNIQUE (user_id, book_mark_name)'];
}

class GroupAndDictLinks extends Table {
  TextColumn get groupId => text()();
  TextColumn get dictId => text()();

  @override
  Set<Column>? get primaryKey => {groupId, dictId};
}

/// 打卡记录
class Dakas extends Table {
  TextColumn get userId => text()();
  DateTimeColumn get forLearningDate => dateTime()();
  TextColumn get textContent => text().nullable()();
  DateTimeColumn get createTime => dateTime()();
  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {userId, forLearningDate};
}

/// 用户操作历史表，记录用户的主要操作：登录、开始学习、打卡
class UserOpers extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get operType => text()(); // 操作类型: LOGIN、START_LEARN、DAKA
  DateTimeColumn get operTime => dateTime()(); // 操作时间
  TextColumn get remark => text().nullable()(); // 备注信息
  DateTimeColumn get createTime => dateTime()();
  DateTimeColumn get updateTime => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 已掌握单词表
class MasteredWords extends Table {
  TextColumn get userId => text()();
  TextColumn get wordId => text()();
  DateTimeColumn get masterAtTime => dateTime()(); // 掌握单词的时间
  DateTimeColumn get createTime => dateTime()();
  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {userId, wordId};
}

class UserCowDungLogs extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  IntColumn get delta => integer()();
  IntColumn get cowDung => integer()();
  DateTimeColumn get theTime => dateTime()();
  TextColumn get reason => text()();

  @override
  Set<Column>? get primaryKey => {id};
}


/// 用户错词表
class UserWrongWords extends Table {
  TextColumn get userId => text()();
  TextColumn get wordId => text()();
  DateTimeColumn get createTime => dateTime()();
  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {userId, wordId};
}

/// 系统数据版本表（单例表，只有一条记录）
class SysDbVersion extends Table {
  TextColumn get id => text().withDefault(const Constant('singleton'))();
  IntColumn get version => integer()();
  DateTimeColumn get lastSyncTime => dateTime().nullable()();
  DateTimeColumn get createTime => dateTime()();
  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}



/// 本地异常记录表
class LocalExceptions extends Table {
  TextColumn get id => text()();

  /// 异常类型（如：Exception, Error, NetworkError等）
  TextColumn get errorType => text()();

  /// 异常消息
  TextColumn get message => text()();

  /// 异常堆栈信息
  TextColumn get stackTrace => text().nullable()();

  /// 错误上下文信息（如：操作类型、页面名称等）
  TextColumn get context => text().nullable()();

  /// 用户ID（如果异常发生时用户已登录）
  TextColumn get userId => text().nullable()();

  /// 创建时间
  DateTimeColumn get createTime => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 学习历史记录表
class LearningLogs extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get wordId => text()();
  IntColumn get rating => integer()(); // 1: Again, 2: Hard, 3: Good, 4: Easy
  RealColumn get stability => real()();
  RealColumn get difficulty => real()();
  IntColumn get elapsedDays => integer()();
  IntColumn get scheduledDays => integer()();
  DateTimeColumn get createTime => dateTime()();
  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
