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

  TextColumn get studyStep =>
      text()(); // 'Word', 'Meaning'

  IntColumn get index => integer()();

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

class VotedChineses extends Table {
  TextColumn get userId => text()();

  TextColumn get chineseId => text()();

  TextColumn get vote => text()(); // 'HAND'/'FOOT'

  @override
  Set<Column>? get primaryKey => {userId, chineseId};
}

class VotedWordImages extends Table {
  TextColumn get userId => text()();

  TextColumn get imageId => text()();

  TextColumn get vote => text()(); // 'HAND'/'FOOT'

  @override
  Set<Column>? get primaryKey => {userId, imageId};
}

class Levels extends Table {
  TextColumn get id => text()();

  IntColumn get level => integer()();

  TextColumn get name => text()();

  TextColumn get figure => text().nullable()();

  IntColumn get minScore => integer()();

  IntColumn get maxScore => integer()();

  TextColumn get style => text()();

  @override
  Set<Column>? get primaryKey => {id};
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

  /// 是否直接显示备选答案
  BoolColumn get showAnswersDirectly => boolean()();

  /// 是否自动朗读单词发音
  BoolColumn get autoPlayWord => boolean()();

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

  IntColumn get lastLearningPosition => integer().nullable()();

  IntColumn get lastLearningMode => integer().nullable()();

  BoolColumn get learningFinished => boolean()();

  BoolColumn get inviteAwardTaken => boolean()();

  BoolColumn get isSuper => boolean()();

  BoolColumn get isAdmin => boolean()();

  BoolColumn get isInputor => boolean()();

  BoolColumn get isTodayLearningStarted => boolean()();

  BoolColumn get isTodayLearningFinished => boolean()();

  BoolColumn get autoPlaySentence => boolean()();

  IntColumn get wordsPerDay => integer()();

  IntColumn get dakaDayCount => integer()();

  IntColumn get masteredWordsCount => integer()();

  IntColumn get cowDung => integer()();

  IntColumn get throwDiceChance => integer()();

  TextColumn get invitedById => text().nullable()();

  /// 用户等级ID
  TextColumn get levelId => text()();

  /// 连续打卡天数
  IntColumn get continuousDakaDayCount => integer()();

  /// 最大连续打卡天数
  IntColumn get maxContinuousDakaDayCount => integer()();

  /// 最近一次打卡的日期
  DateTimeColumn get lastDakaDate => dateTime().nullable()();

  IntColumn get totalScore => integer()();

  RealColumn get dakaRatio => real().nullable()();

  BoolColumn get enableAllWrong => boolean()();

  // 旧字段 passIfSpeakOutOneMeaning 已移除

  @override
  Set<Column> get primaryKey => {id};
}

class LearningDicts extends Table {
  TextColumn get userId => text()();

  TextColumn get dictId => text()();

  BoolColumn get isPrivileged => boolean()();
  BoolColumn get fetchMastered => boolean()();

  TextColumn get currentWordId => text().nullable()();

  /// 当前已取词位置
  IntColumn get currentWordSeq => integer().nullable()();

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

  TextColumn get ownerId => text()();

  BoolColumn get visible => boolean()();

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

  TextColumn get table_ => text()();

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

  TextColumn get wordId => text()();

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

  DateTimeColumn get updateTime => dateTime().nullable()();

  @override
  Set<Column>? get primaryKey => {id};
}

class Sentences extends Table {
  TextColumn get id => text()();

  TextColumn get english => text()();

  TextColumn get chinese => text()();
  TextColumn get englishDigest => text()();
  TextColumn get theType => text()();

  IntColumn get handCount => integer()();

  IntColumn get footCount => integer()();

  TextColumn get authorId => text()();

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

  /// 生命值(需要学习的次数)，0-5，0表示已掌握，1-5表示需要学习
  IntColumn get lifeValue => integer()();

  BoolColumn get isTodayNewWord => boolean()();
  IntColumn get learnedTimes => integer()();

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
  List<String> get customConstraints => [
    'UNIQUE (user_id, book_mark_name)'
  ];
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

// UserStageWords table has been removed - StageWord functionality is no longer used

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

/// 单词短描述中文翻译表
class WordShortDescChineses extends Table {
  TextColumn get id => text()();
  TextColumn get wordId => text()();
  TextColumn get content => text()();
  IntColumn get hand => integer()();
  IntColumn get foot => integer()();
  TextColumn get author => text()();
  DateTimeColumn get createTime => dateTime()();
  DateTimeColumn get updateTime => dateTime().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}
