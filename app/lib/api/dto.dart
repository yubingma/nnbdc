import 'package:json_annotation/json_annotation.dart';
import 'package:nnbdc/util/custom_convert.dart';
part 'dto.g.dart';

@JsonSerializable()
@CustomDateTimeConverter()
class DictDto {
  String id;
  bool isReady;
  bool isShared;
  String name;
  int wordCount;
  String ownerId;
  bool visible;
  bool? editable;
  bool? deletable;
  int? popularityLimit;
  String? domain;
  String? baseDictId;
  String? sortAlg;
  DateTime createTime;
  DateTime updateTime;

  DictDto(this.id, this.isReady, this.isShared, this.name, this.wordCount, this.ownerId, this.visible, this.popularityLimit, this.createTime,
      this.updateTime, [this.editable, this.deletable, this.domain, this.baseDictId, this.sortAlg]);

  factory DictDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$DictDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$DictDtoToJson(this);

  String getShortName() {
    if (name.endsWith(".dict")) {
      return name.substring(0, name.lastIndexOf("."));
    } else {
      return name;
    }
  }
}

@JsonSerializable()
@CustomDateTimeConverter()
class DictWordDto {
  final String dictId;
  final String wordId;
  final int seq;
  final int unit;
  final DateTime createTime;
  final DateTime updateTime;

  DictWordDto(this.dictId, this.wordId, this.seq, this.createTime, this.updateTime, [this.unit = 0]);

  factory DictWordDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$DictWordDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$DictWordDtoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class WordDto {
  final String id;
  final String? americaPronounce;
  final String? britishPronounce;
  final String? groupInfo;
  final String? longDesc;
  final int popularity;
  final String? pronounce;
  final String? shortDesc;
  final String spell;
  final DateTime createTime;
  final DateTime updateTime;

  WordDto(this.id, this.americaPronounce, this.britishPronounce, this.groupInfo, this.longDesc, this.popularity, this.pronounce, this.shortDesc,
      this.spell, this.createTime, this.updateTime);

  factory WordDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$WordDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$WordDtoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class MeaningItemDto {
  final String id;
  final String wordId;
  final String? dictId;
  final String ciXing;
  final String meaning;
  final int popularity;
  final String? ownerId;
  final DateTime createTime;
  final DateTime updateTime;

  MeaningItemDto(this.id, this.wordId, this.dictId, this.ciXing, this.meaning, this.popularity, this.ownerId, this.createTime, this.updateTime);

  factory MeaningItemDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$MeaningItemDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$MeaningItemDtoToJson(this);
}

@JsonSerializable()
class SimilarWordDto {
  final String wordId;
  final String similarWordId;
  final String similarWordSpell;
  final int distance;
  final DateTime createTime;
  final DateTime updateTime;

  SimilarWordDto(this.wordId, this.similarWordId, this.similarWordSpell, this.distance, this.createTime, this.updateTime);

  factory SimilarWordDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$SimilarWordDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$SimilarWordDtoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class SynonymDto {
  final String meaningItemId;
  final String wordId;
  final String spell;
  final DateTime createTime;
  final DateTime updateTime;

  SynonymDto(this.meaningItemId, this.wordId, this.spell, this.createTime, this.updateTime);

  factory SynonymDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$SynonymDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$SynonymDtoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class SentenceDto {
  final String id;
  final String english;
  final String chinese;
  final String englishDigest;
  final String theType;
  final int handCount;
  final int footCount;
  final String? authorId;
  final String? ownerId;
  final String meaningItemId;
  final String wordMeaning;
  final DateTime createTime;
  final DateTime updateTime;

  final String? ttsVoice;
  final String? ttsEngine;

  SentenceDto(
      this.id,
      this.english,
      this.chinese,
      this.englishDigest,
      this.theType,
      this.handCount,
      this.footCount,
      this.authorId,
      this.ownerId,
      this.meaningItemId,
      this.wordMeaning,
      this.createTime,
      this.updateTime,
      this.ttsVoice,
      this.ttsEngine);

  factory SentenceDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$SentenceDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$SentenceDtoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class WordImageDto {
  final String id;
  final String imageFile;
  final int foot;
  final int hand;
  final String? authorId;
  final String? ownerId;
  final String wordId;
  final DateTime createTime;
  final DateTime updateTime;

  WordImageDto(this.id, this.imageFile, this.foot, this.hand, this.authorId, this.ownerId, this.wordId, this.createTime, this.updateTime);

  factory WordImageDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$WordImageDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$WordImageDtoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class VerbTenseDto {
  final String id;
  final String tenseType;
  final String? tensedSpell;
  final String? wordId;
  final DateTime createTime;
  final DateTime updateTime;

  VerbTenseDto(this.id, this.tenseType, this.tensedSpell, this.wordId, this.createTime, this.updateTime);

  factory VerbTenseDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$VerbTenseDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$VerbTenseDtoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class CigenDto {
  final String id;
  final String description;
  final String? spell;
  final String? category;
  final String? meaningCn;
  final String? meaningEn;
  final DateTime createTime;
  final DateTime updateTime;

  CigenDto(this.id, this.description, this.createTime, this.updateTime, {this.spell, this.category, this.meaningCn, this.meaningEn});

  factory CigenDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$CigenDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$CigenDtoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class CigenWordLinkDto {
  final String cigenId;
  final String wordId;
  final String theExplain;
  final DateTime createTime;
  final DateTime updateTime;

  CigenWordLinkDto(this.cigenId, this.wordId, this.theExplain, this.createTime, this.updateTime);

  factory CigenWordLinkDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$CigenWordLinkDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$CigenWordLinkDtoToJson(this);
}

@JsonSerializable()
class DictRes {
  DictDto? dict;
  List<DictWordDto>? dictWords;
  List<WordDto>? words;
  List<MeaningItemDto>? meaningItems;
  List<SimilarWordDto>? similarWords;
  List<SynonymDto>? synonyms;
  List<SentenceDto>? sentences;
  List<WordImageDto>? images;
  List<VerbTenseDto>? verbTenses;
  List<CigenDto>? cigens;
  List<CigenWordLinkDto>? cigenWordLinks;

  DictRes(
      {this.dict,
      this.dictWords,
      this.words,
      this.meaningItems,
      this.similarWords,
      this.synonyms,
      this.sentences,
      this.images,
      this.verbTenses,
      this.cigens,
      this.cigenWordLinks});

  factory DictRes.fromJson(Map<String, dynamic> json) => _$DictResFromJson(json);

  Map<String, dynamic> toJson() => _$DictResToJson(this);
}

// 系统数据DTO
@JsonSerializable()
class SystemDataDto {
  int version;
  List<LevelDto> levels;
  List<DictGroupDto>? dictGroups;
  List<GroupAndDictLinkDto>? groupAndDictLinks;
  List<DictDto>? dicts;

  SystemDataDto({
    required this.version,
    required this.levels,
    this.dictGroups,
    this.groupAndDictLinks,
    this.dicts,
  });

  factory SystemDataDto.fromJson(Map<String, dynamic> json) => _$SystemDataDtoFromJson(json);

  Map<String, dynamic> toJson() => _$SystemDataDtoToJson(this);
}

@JsonSerializable()
class UserDbLogDto {
  String id;
  String userId;
  int version;
  String operate;
  String tblName;
  String recordId;
  String record;
  @CustomDateTimeConverter()
  DateTime createTime;
  @CustomDateTimeConverter()
  DateTime updateTime;

  UserDbLogDto(this.id, this.userId, this.version, this.operate, this.tblName, this.recordId, this.record, this.createTime, this.updateTime);

  factory UserDbLogDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$UserDbLogDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$UserDbLogDtoToJson(this);
}

// 用户等级DTO
@JsonSerializable()
class LevelDto {
  final String id;
  final int level;
  final String name;
  final String? figure;
  final int minScore;
  final int maxScore;
  final String style;

  LevelDto({
    required this.id,
    required this.level,
    required this.name,
    this.figure,
    required this.minScore,
    required this.maxScore,
    required this.style,
  });

  factory LevelDto.fromJson(Map<String, dynamic> json) => _$LevelDtoFromJson(json);

  Map<String, dynamic> toJson() => _$LevelDtoToJson(this);
}

// 单词书分组DTO
@JsonSerializable()
class DictGroupDto {
  final String id;
  final String name;
  final String? parentId;
  final int displayIndex;

  DictGroupDto({
    required this.id,
    required this.name,
    this.parentId,
    required this.displayIndex,
  });

  factory DictGroupDto.fromJson(Map<String, dynamic> json) => _$DictGroupDtoFromJson(json);

  Map<String, dynamic> toJson() => _$DictGroupDtoToJson(this);
}

// 单词书分组与词书关联DTO
@JsonSerializable()
@CustomDateTimeConverter()
class GroupAndDictLinkDto {
  final String groupId;
  final String dictId;

  GroupAndDictLinkDto({
    required this.groupId,
    required this.dictId,
  });

  factory GroupAndDictLinkDto.fromJson(Map<String, dynamic> json) => _$GroupAndDictLinkDtoFromJson(json);

  Map<String, dynamic> toJson() => _$GroupAndDictLinkDtoToJson(this);
}

/// 字符串列表包装类，用于在retrofit中序列化`List<String>`
class StringList {
  List<String> items;

  StringList(this.items);

  /// 便捷构造方法，从`List<String>`创建`StringList`
  static StringList from(List<String> list) {
    return StringList(list);
  }

  factory StringList.fromJson(Map<String, dynamic> json) {
    return StringList(
      (json['items'] as List).map((e) => e as String).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'items': items,
    };
  }
}

/// JSON Map包装类，用于在retrofit中序列化`Map<String, dynamic>`
class JsonMap {
  Map<String, dynamic> data;

  JsonMap(this.data);

  /// 便捷构造方法，从`Map<String, dynamic>`创建`JsonMap`
  static JsonMap from(Map<String, dynamic> map) {
    return JsonMap(map);
  }

  factory JsonMap.fromJson(Map<String, dynamic> json) {
    // 直接返回整个json对象作为data
    return JsonMap(json);
  }

  Map<String, dynamic> toJson() {
    // 直接返回data字段
    return data;
  }
}

@JsonSerializable()
@CustomDateTimeConverter()
class UserCowDungLogDto {
  String userId;
  int delta;
  String reason;
  DateTime theTime;
  DateTime createTime;
  DateTime updateTime;

  UserCowDungLogDto(this.userId, this.delta, this.reason, this.theTime, this.createTime, this.updateTime);

  factory UserCowDungLogDto.fromJson(Map<String, dynamic> json) => _$UserCowDungLogDtoFromJson(json);

  Map<String, dynamic> toJson() => _$UserCowDungLogDtoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class UserDto {
  String? id;
  String? userName;
  String? nickName;
  String? password;
  DateTime? lastLoginTime;
  DateTime? lastShareTime;
  String? email;
  String? wechatOpenId;
  String? wechatUnionId;
  String? wechatNickname;
  String? wechatAvatar;
  DateTime? lastLearningDate;
  int? learnedDays;
  bool? learningFinished;
  bool? inviteAwardTaken;
  bool? isSuperAdmin;
  bool? isAdmin;
  bool? isInputor;
  bool? isSysUser;
  int? wordsPerDay;
  int? dakaDayCount;
  int? masteredWordsCount;
  int? cowDung;
  int? throwDiceChance;
  int? gameScore;
  int? continuousDakaDayCount;
  int? maxContinuousDakaDayCount;
  DateTime? lastDakaDate;
  int? dakaScore;
  bool? isTodayLearningStarted;
  bool? isTodayLearningFinished;
  String? appleUserId;
  String? studyConfig;
  late DateTime createTime;
  late DateTime updateTime;

  UserDto();

  factory UserDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$UserDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$UserDtoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class SysDbLogDto {
  final String id;
  final int version;
  final String operate;
  final String tblName;
  final String recordId;
  final String record;
  final DateTime createTime;
  final DateTime updateTime;

  SysDbLogDto(
    this.id,
    this.version,
    this.operate,
    this.tblName,
    this.recordId,
    this.record,
    this.createTime,
    this.updateTime,
  );

  factory SysDbLogDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$SysDbLogDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$SysDbLogDtoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class WordShortDescChineseDto {
  final String id;
  final String wordId;
  final String content;
  final int hand;
  final int foot;
  final String author;
  final String ownerId;
  final DateTime createTime;
  final DateTime updateTime;

  WordShortDescChineseDto(
    this.id,
    this.wordId,
    this.content,
    this.hand,
    this.foot,
    this.author,
    this.ownerId,
    this.createTime,
    this.updateTime,
  );

  factory WordShortDescChineseDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$WordShortDescChineseDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$WordShortDescChineseDtoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class UserStudyStepDto {
  final String userId;
  final String studyStep;
  final int seq;
  final String state;
  final DateTime createTime;
  final DateTime updateTime;

  UserStudyStepDto(this.userId, this.studyStep, this.seq, this.state, this.createTime, this.updateTime);

  factory UserStudyStepDto.fromJson(Map<String, dynamic> json) {
    json['updateTime'] ??= json['createTime'];
    return _$UserStudyStepDtoFromJson(json);
  }

  Map<String, dynamic> toJson() => _$UserStudyStepDtoToJson(this);
}



